import AppKit
import MuralKit
import Synchronization
import Testing

@testable import Mural

/// Cada teste usa uma área de transferência nomeada só dele e um `accessBehavior` trocado: o aviso "Permitir colar?" só existe
/// na área de transferência geral. Para provar que o conteúdo não foi lido, os dados saem de um provedor que conta quantas
/// vezes foram pedidos.
@MainActor
@Suite("Leitor da área de transferência do painel", .serialized)
struct ClipboardReaderTests {
    private typealias Payload = (type: NSPasteboard.PasteboardType, data: Data)

    /// Entrega os dados só quando alguém os pede, e conta os pedidos.
    private final class CountingProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {
        private let payloads: [Payload]
        private let requests = Mutex(0)

        init(_ payloads: [Payload]) {
            self.payloads = payloads
            super.init()
        }

        var requestCount: Int { requests.withLock { $0 } }

        func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
            requests.withLock { $0 += 1 }
            guard let payload = payloads.first(where: { $0.type == type }) else { return }
            item.setData(payload.data, forType: type)
        }
    }

    private static let text = "Olá, mural"

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: .init("mural-teste-\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    private func makeReader(_ pasteboard: NSPasteboard, _ behavior: NSPasteboard.AccessBehavior) -> ClipboardReader {
        ClipboardReader(pasteboard: pasteboard, accessBehavior: { _ in behavior })
    }

    /// Escreve um item cujos dados só saem quando pedidos. `marker` é um tipo extra e vazio, como o dos apps de senha.
    private func writeLazily(_ payloads: [Payload], marker: String? = nil, to pasteboard: NSPasteboard) throws -> CountingProvider {
        let provider = CountingProvider(payloads)
        let item = NSPasteboardItem()
        try #require(item.setDataProvider(provider, forTypes: payloads.map(\.type)))
        if let marker { try #require(item.setString("", forType: .init(marker))) }
        try #require(pasteboard.writeObjects([item]))
        // Escrever não pode ler: sem isto, as provas de "não leu" dos testes não valeriam nada.
        try #require(provider.requestCount == 0)
        return provider
    }

    // MARK: Texto

    @Test("Texto com .default ou .ask: abrir só olha os tipos; colar lê", arguments: [NSPasteboard.AccessBehavior.default, .ask])
    func textIsReadOnlyWhenPasting(behavior: NSPasteboard.AccessBehavior) throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let provider = try writeLazily([(.string, Data(Self.text.utf8))], to: pasteboard)
        let reader = makeReader(pasteboard, behavior)

        let peeked = reader.peek()
        #expect(peeked.state == .available(.text(nil)))
        #expect(peeked.content == nil)
        #expect(provider.requestCount == 0)

        let pasted = reader.read()
        #expect(pasted.state == .available(.text(Self.text)))
        guard case .pasted(.text(let text))? = pasted.content else {
            Issue.record("Esperava .pasted(.text), veio \(String(describing: pasted.content))")
            return
        }
        #expect(text == Self.text)
        #expect(provider.requestCount > 0)
    }

    @Test("Texto com .alwaysAllow: abrir já lê, porque não há aviso")
    func textIsReadOnPeekWhenAlwaysAllowed() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let provider = try writeLazily([(.string, Data(Self.text.utf8))], to: pasteboard)

        let peeked = makeReader(pasteboard, .alwaysAllow).peek()

        #expect(peeked.state == .available(.text(Self.text)))
        guard case .pasted(.text(let text))? = peeked.content else {
            Issue.record("Esperava .pasted(.text), veio \(String(describing: peeked.content))")
            return
        }
        #expect(text == Self.text)
        #expect(provider.requestCount > 0)
    }

    // MARK: Leitura negada

    @Test("Leitura negada pelo sistema: abrir não lê nada")
    func deniedPeekDoesNotRead() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let provider = try writeLazily([(.string, Data(Self.text.utf8))], to: pasteboard)

        let peeked = makeReader(pasteboard, .alwaysDeny).peek()

        #expect(peeked.state == .deniedBySystem)
        #expect(peeked.content == nil)
        #expect(provider.requestCount == 0)
    }

    @Test("Leitura negada: colar ainda lê (o ⌘V é da pessoa), e sem nada lido o motivo é a negação")
    func deniedReadStillReads() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let reader = makeReader(pasteboard, .alwaysDeny)

        // A leitura negada volta vazia, o que não se distingue de uma área de transferência vazia.
        let empty = reader.read()
        #expect(empty.state == .deniedBySystem)
        #expect(empty.content == nil)

        let provider = try writeLazily([(.string, Data(Self.text.utf8))], to: pasteboard)
        let pasted = reader.read()
        #expect(pasted.state == .available(.text(Self.text)))
        #expect(pasted.content != nil)
        #expect(provider.requestCount > 0)
    }

    // MARK: Privado e temporário

    @Test(
        "Marca de privado ou temporário: nunca é lido, nem com a leitura liberada",
        arguments: ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"],
        [NSPasteboard.AccessBehavior.alwaysAllow, .alwaysDeny])
    func protectedContentIsNeverRead(marker: String, behavior: NSPasteboard.AccessBehavior) throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let provider = try writeLazily([(.string, Data("senha".utf8))], marker: marker, to: pasteboard)
        let reader = makeReader(pasteboard, behavior)

        for reading in [reader.peek(), reader.read()] {
            #expect(reading.state == .protected)
            #expect(reading.content == nil)
        }
        #expect(provider.requestCount == 0)
    }

    // MARK: Nada para colar

    @Test("Área de transferência vazia: nada para colar")
    func emptyPasteboard() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let reader = makeReader(pasteboard, .default)

        for reading in [reader.peek(), reader.read()] {
            #expect(reading.state == .nothing)
            #expect(reading.content == nil)
        }
    }

    @Test("Só um tipo que o mural não cola: nada para colar, e nem com .alwaysAllow se chega a ler")
    func unsupportedTypeIsNotRead() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let provider = try writeLazily([(.html, Data("<b>negrito</b>".utf8))], to: pasteboard)

        let peeked = makeReader(pasteboard, .alwaysAllow).peek()

        #expect(peeked.state == .nothing)
        #expect(peeked.content == nil)
        #expect(provider.requestCount == 0)
    }

    // MARK: Palpite pelos tipos

    @Test("Imagem PNG: o palpite é imagem e abrir não lê os dados")
    func pngGuess() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let png = try TestImage.png(width: 4, height: 4)
        let provider = try writeLazily([(.png, png)], to: pasteboard)
        let reader = makeReader(pasteboard, .default)

        let peeked = reader.peek()
        #expect(peeked.state == .available(.image))
        #expect(peeked.content == nil)
        #expect(provider.requestCount == 0)

        let pasted = reader.read()
        #expect(pasted.state == .available(.image))
        guard case .pasted(.data(let data, let fileExtension, let kind, _))? = pasted.content else {
            Issue.record("Esperava .pasted(.data), veio \(String(describing: pasted.content))")
            return
        }
        #expect(data == png)
        #expect(fileExtension == "png")
        #expect(kind == .image)
        #expect(provider.requestCount > 0)
    }

    @Test("Endereço: o palpite é link sem contagem; colar lê um link")
    func addressGuessAndRead() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let address = try #require(URL(string: "https://exemplo.com/pagina"))
        let provider = try writeLazily([(.URL, Data(address.absoluteString.utf8))], to: pasteboard)
        let reader = makeReader(pasteboard, .default)

        let peeked = reader.peek()
        #expect(peeked.state == .available(.links(count: 0)))
        #expect(peeked.content == nil)
        #expect(provider.requestCount == 0)

        let pasted = reader.read()
        #expect(pasted.state == .available(.links(count: 1)))
        guard case .pasted(.links(let links))? = pasted.content else {
            Issue.record("Esperava .pasted(.links), veio \(String(describing: pasted.content))")
            return
        }
        #expect(links.map(\.url) == [address])
        #expect(provider.requestCount > 0)
    }

    @Test("Link do Apple Music sem os tipos do Música: o palpite é link, e a leitura vira música")
    func appleMusicLinkBecomesMusicOnRead() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let address = "https://music.apple.com/br/album/album-de-teste/111?l=en-GB"
        let provider = try writeLazily([(.URL, Data(address.utf8))], to: pasteboard)
        let reader = makeReader(pasteboard, .default)

        #expect(reader.peek().state == .available(.links(count: 0)))
        #expect(provider.requestCount == 0)

        let pasted = reader.read()
        #expect(pasted.state == .available(.music(count: 1)))
        guard case .music(let drafts)? = pasted.content else {
            Issue.record("Esperava .music, veio \(String(describing: pasted.content))")
            return
        }
        #expect(drafts.count == 1)
    }

    @Test("Tipo do Música: o palpite é música sem contagem; dados que não servem desmentem o palpite ao ler")
    func musicTypeGuess() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let provider = try writeLazily([(.init("com.apple.tv.metadata"), Data("qualquer coisa".utf8))], to: pasteboard)
        let reader = makeReader(pasteboard, .default)

        let peeked = reader.peek()
        #expect(peeked.state == .available(.music(count: 0)))
        #expect(peeked.content == nil)
        #expect(provider.requestCount == 0)

        let pasted = reader.read()
        #expect(pasted.state == .nothing)
        #expect(pasted.content == nil)
        #expect(provider.requestCount > 0)
    }

    // MARK: Tipo do conteúdo lido

    @Test("O tipo de cada conteúdo lido")
    func kindOfContent() throws {
        let file = URL(fileURLWithPath: "/arquivo-de-teste.txt")
        let link = LinkDraft(url: try #require(URL(string: "https://exemplo.com")))
        let draft = MusicDraft(snapshot: MusicSnapshot(kind: .album, title: "Álbum de teste"))
        let table: [(label: String, content: ClipboardContent, expected: ClipboardKind)] = [
            ("música", .music([draft, draft]), .music(count: 2)),
            ("arquivos", .pasted(.files([file, file, file])), .files(count: 3)),
            ("PNG", .pasted(.data(Data(), fileExtension: "png", kind: .image, title: "Imagem colada")), .image),
            ("imagem a converter", .pasted(.imageNeedingConversion(Data())), .image),
            ("PDF", .pasted(.data(Data(), fileExtension: "pdf", kind: .pdf, title: "PDF colado")), .pdf),
            ("outro dado (vídeo)", .pasted(.data(Data(), fileExtension: "mov", kind: .video, title: "Vídeo")), .files(count: 1)),
            ("links", .pasted(.links([link, link])), .links(count: 2)),
            ("texto", .pasted(.text("Olá")), .text("Olá")),
            ("nada", .pasted(.nothing), .nothing),
        ]

        for row in table {
            #expect(ClipboardReader.kind(of: row.content) == row.expected, "\(row.label)")
        }
    }

    // MARK: Identificadores de tipo

    @Test("Os tipos de mais de um item entram na lista, sem repetir")
    func typeIdentifiersJoinItems() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let first = NSPasteboardItem()
        first.setString("a", forType: .string)
        first.setString("https://exemplo.com", forType: .URL)
        let second = NSPasteboardItem()
        second.setString("b", forType: .string)
        second.setData(Data([1, 2, 3]), forType: .png)
        pasteboard.writeObjects([first, second])

        let identifiers = ClipboardReader.typeIdentifiers(of: pasteboard)

        let expected = [NSPasteboard.PasteboardType.string, .URL, .png].map(\.rawValue)
        #expect(Set(identifiers).isSuperset(of: expected))
        #expect(identifiers.count == Set(identifiers).count)
    }
}
