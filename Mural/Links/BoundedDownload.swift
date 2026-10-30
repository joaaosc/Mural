import Foundation
import MuralKit
import Synchronization

/// Baixa uma resposta HTTP aos poucos e interrompe a transferência quando já tem o que precisa ou quando
/// ela passa do limite, em vez de esperar o fim do arquivo.
///
/// `URLSession.bytes(for:)` não serve para isso: medido neste Mac, percorrer 5 MB byte a byte leva mais de
/// 30 s, enquanto o delegado recebe blocos inteiros. O delegado é o da própria tarefa (`URLSessionTask.delegate`),
/// então funciona com qualquer `URLSession`, inclusive a injetada nos testes.
nonisolated final class BoundedDownload: NSObject, URLSessionDataDelegate, Sendable {
    /// O que fazer com o corpo, decidido quando o cabeçalho da resposta chega.
    struct Plan: Sendable {
        /// Máximo de bytes do corpo que interessam.
        var maximumBytes: Int
        /// Com `true`, um corpo maior que o máximo faz o download falhar com `URLError.dataLengthExceedsMaximum`,
        /// já pelo `Content-Length` quando ele anuncia mais que o máximo. Com `false`, o corpo é cortado no
        /// máximo e o que veio até ali é entregue.
        var failsAboveMaximum: Bool
        /// Se aparecer no corpo, a transferência para ali e o que já veio é entregue. Em minúsculas e ASCII; a
        /// busca não diferencia maiúsculas de minúsculas.
        var endMarker: [UInt8]?
    }

    /// O corpo guardado e a resposta que o acompanhou.
    struct Output: Sendable {
        var data: Data
        var response: HTTPURLResponse
    }

    /// Como a transferência terminou por decisão daqui (e não por fim do corpo ou erro de rede).
    private enum Ending: Sendable {
        /// Já tem o que precisava, ou não há corpo a ler.
        case enough
        case failed(any Error)
    }

    private struct State: Sendable {
        var task: URLSessionDataTask?
        var continuation: CheckedContinuation<Output, any Error>?
        /// A tarefa Swift que espera este download foi cancelada.
        var isCancelled = false
        var response: HTTPURLResponse?
        var plan: Plan?
        var data = Data()
        /// Quantos bytes de `data` já foram examinados à procura do marcador de fim.
        var scannedBytes = 0
        var ending: Ending?

        /// O resultado final, quando a tarefa de rede termina com `completionError` (ou sem erro).
        func outcome(completionError: (any Error)?) -> Result<Output, any Error> {
            if isCancelled { return .failure(CancellationError()) }
            switch ending {
            case .failed(let error)?:
                return .failure(error)
            case .enough?:
                break
            case nil:
                if let completionError { return .failure(completionError) }
            }
            guard let response else { return .failure(URLError(.badServerResponse)) }
            return .success(Output(data: data, response: response))
        }
    }

    private let makePlan: @Sendable (HTTPURLResponse) throws -> Plan?
    private let state = Mutex(State())

    private init(makePlan: @escaping @Sendable (HTTPURLResponse) throws -> Plan?) {
        self.makePlan = makePlan
        super.init()
    }

    /// Baixa a resposta de `request`.
    /// - Parameter plan: recebe a resposta assim que o cabeçalho chega e decide o que ler do corpo. Devolver
    ///   `nil` encerra a transferência sem ler o corpo (`data` vem vazio); lançar um erro faz o download falhar.
    /// - Throws: `CancellationError` se a tarefa for cancelada; o erro de `plan`; `URLError` de rede ou de limite.
    static func load(
        _ request: URLRequest, using session: URLSession, plan: @escaping @Sendable (HTTPURLResponse) throws -> Plan?
    ) async throws -> Output {
        let download = BoundedDownload(makePlan: plan)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, any Error>) in
                download.start(request, using: session, continuation: continuation)
            }
        } onCancel: {
            download.cancel()
        }
    }

    // MARK: Ciclo de vida

    private func start(_ request: URLRequest, using session: URLSession, continuation: CheckedContinuation<Output, any Error>) {
        let task = session.dataTask(with: request)
        task.delegate = self
        let wasCancelled = state.withLock { state -> Bool in
            if state.isCancelled { return true }
            state.task = task
            state.continuation = continuation
            return false
        }
        if wasCancelled {
            // O cancelamento chegou antes da tarefa de rede existir: nada foi iniciado.
            task.cancel()
            continuation.resume(throwing: CancellationError())
        } else {
            task.resume()
        }
    }

    private func cancel() {
        let task = state.withLock { state -> URLSessionDataTask? in
            state.isCancelled = true
            return state.task
        }
        task?.cancel()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            state.withLock { $0.ending = .failed(URLError(.badServerResponse)) }
            completionHandler(.cancel)
            return
        }
        let decision = Result { try makePlan(http) }
        let disposition = state.withLock { state -> URLSession.ResponseDisposition in
            state.response = http
            switch decision {
            case .failure(let error):
                state.ending = .failed(error)
                return .cancel
            case .success(.none):
                state.ending = .enough
                return .cancel
            case .success(.some(let plan)):
                if plan.failsAboveMaximum, http.expectedContentLength > Int64(plan.maximumBytes) {
                    state.ending = .failed(URLError(.dataLengthExceedsMaximum))
                    return .cancel
                }
                state.plan = plan
                return .allow
            }
        }
        completionHandler(disposition)
    }

    /// Segue o redirecionamento só se o destino também for da internet pública: uma página pública não pode
    /// mandar a busca para a rede local. Recusado, a resposta do redirecionamento é a que vale (e o status
    /// 3xx faz a busca falhar como falha comum).
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        if let url = request.url, NetworkAddressPolicy.isPublicWebAddress(url) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let shouldStop = state.withLock { state -> Bool in
            guard state.ending == nil, let plan = state.plan else { return false }

            let room = plan.maximumBytes - state.data.count
            if data.count > room {
                if plan.failsAboveMaximum {
                    state.data = Data()
                    state.ending = .failed(URLError(.dataLengthExceedsMaximum))
                } else {
                    state.data.append(data.prefix(room))
                    state.ending = .enough
                }
                return true
            }

            state.data.append(data)
            guard let marker = plan.endMarker else { return false }
            if Self.contains(marker, in: state.data, from: state.scannedBytes) {
                state.ending = .enough
                return true
            }
            // O marcador pode começar no fim deste bloco e terminar no próximo.
            state.scannedBytes = max(0, state.data.count - marker.count + 1)
            return false
        }
        if shouldStop { dataTask.cancel() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, outcome) = state.withLock { state in
            let continuation = state.continuation
            state.continuation = nil
            return (continuation, state.outcome(completionError: error))
        }
        continuation?.resume(with: outcome)
    }

    // MARK: Marcador

    /// Indica se `marker` (minúsculas, ASCII) aparece em `bytes` a partir de `start`, sem diferenciar maiúsculas.
    private static func contains(_ marker: [UInt8], in bytes: Data, from start: Int) -> Bool {
        guard !marker.isEmpty, bytes.count - start >= marker.count else { return false }
        return bytes.withUnsafeBytes { buffer in
            let lastStart = buffer.count - marker.count
            var index = start
            while index <= lastStart {
                var matches = true
                for offset in 0..<marker.count where lowercased(buffer[index + offset]) != marker[offset] {
                    matches = false
                    break
                }
                if matches { return true }
                index += 1
            }
            return false
        }
    }

    private static func lowercased(_ byte: UInt8) -> UInt8 {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) ? byte + 32 : byte
    }
}
