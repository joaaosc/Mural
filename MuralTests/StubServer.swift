import Foundation
import Synchronization

/// Servidor falso de um teste: responde, sem rede, aos endereços de um host só dele (`stub-<uuid>.test`).
/// Como cada teste tem o seu host, os testes rodam em paralelo sem se misturar.
///
/// Para valer, a sessão precisa usar `StubURLProtocol.session(configuration:)`.
final class StubServer: Sendable {
    /// O que o servidor responde a um caminho.
    struct Reply: Sendable {
        var status = 200
        var contentType: String? = "text/html; charset=utf-8"
        /// Outros cabeçalhos, por exemplo `Content-Length`; nenhum é acrescentado sozinho.
        var headers: [String: String] = [:]
        var body = Data()
        /// Depois do corpo a resposta não termina: fica parada até a transferência ser cancelada.
        var staysOpen = false
        /// Nem começa a responder: fica parada até a transferência ser cancelada.
        var neverAnswers = false
        /// Em vez de responder, falha com este erro de rede.
        var failure: URLError.Code?
        /// Em vez de responder, redireciona (301) para este caminho.
        var redirect: String?
    }

    /// Uma requisição que chegou ao servidor.
    struct Recorded: Sendable {
        var url: URL
        var headers: [String: String]
    }

    private struct State {
        var routes: [String: Reply] = [:]
        var requests: [Recorded] = []
        var interruptedPaths: [String] = []
    }

    let host = "stub-\(UUID().uuidString.lowercased()).test"
    private let state = Mutex(State())

    init() {
        StubURLProtocol.register(self)
    }

    // MARK: Rotas

    func respond(_ path: String, _ reply: Reply) {
        state.withLock { $0.routes[path] = reply }
    }

    func respond(_ path: String, html: String) {
        respond(path, Reply(body: Data(html.utf8)))
    }

    func respond(_ path: String, image: Data, contentType: String = "image/png", headers: [String: String] = [:]) {
        respond(path, Reply(contentType: contentType, headers: headers, body: image))
    }

    func respond(_ path: String, status: Int) {
        respond(path, Reply(status: status, contentType: "text/plain"))
    }

    // MARK: Endereços

    func url(_ path: String, scheme: String = "https") -> URL {
        URL(string: "\(scheme)://\(host)\(path)")!
    }

    // MARK: O que chegou

    var requests: [Recorded] { state.withLock { $0.requests } }

    /// Os caminhos pedidos, na ordem.
    var requestedPaths: [String] { requests.map { $0.url.path(percentEncoded: false) } }

    /// Caminhos cuja transferência foi interrompida pelo cliente antes de terminar.
    var interruptedPaths: [String] { state.withLock { $0.interruptedPaths } }

    // MARK: Uso interno do protocolo

    fileprivate func record(_ request: URLRequest) {
        guard let url = request.url else { return }
        state.withLock { $0.requests.append(Recorded(url: url, headers: request.allHTTPHeaderFields ?? [:])) }
    }

    fileprivate func reply(for url: URL) -> Reply {
        let path = url.path(percentEncoded: false)
        return state.withLock { $0.routes[path] } ?? Reply(status: 404, contentType: "text/plain")
    }

    fileprivate func noteInterrupted(_ url: URL) {
        state.withLock { $0.interruptedPaths.append(url.path(percentEncoded: false)) }
    }
}

/// Protocolo que entrega as requisições aos `StubServer`s, pelo host.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let servers = Mutex<[String: StubServer]>([:])

    fileprivate static func register(_ server: StubServer) {
        servers.withLock { $0[server.host] = server }
    }

    /// Sessão que entrega as requisições aos `StubServer`s em vez da rede.
    static func session(configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func server(for url: URL?) -> StubServer? {
        guard let host = url?.host else { return nil }
        return servers.withLock { $0[host] }
    }

    /// Verdadeiro quando a resposta chegou ao fim; `stopLoading` sem isso é uma transferência interrompida.
    private let isFinished = Mutex(false)

    override class func canInit(with request: URLRequest) -> Bool {
        server(for: request.url) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url, let server = Self.server(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        server.record(request)
        let reply = server.reply(for: url)

        if reply.neverAnswers { return }
        if let code = reply.failure {
            finish { $0.urlProtocol(self, didFailWithError: URLError(code)) }
            return
        }
        if let redirect = reply.redirect, let target = URL(string: redirect, relativeTo: url)?.absoluteURL {
            let response = HTTPURLResponse(
                url: url, statusCode: 301, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            finish { $0.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response) }
            return
        }

        var headers = reply.headers
        if let contentType = reply.contentType { headers["Content-Type"] = contentType }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty { client?.urlProtocol(self, didLoad: reply.body) }
        if !reply.staysOpen { finish { $0.urlProtocolDidFinishLoading(self) } }
    }

    override func stopLoading() {
        guard !isFinished.withLock({ $0 }), let url = request.url else { return }
        Self.server(for: url)?.noteInterrupted(url)
    }

    private func finish(_ notify: (any URLProtocolClient) -> Void) {
        isFinished.withLock { $0 = true }
        if let client { notify(client) }
    }
}
