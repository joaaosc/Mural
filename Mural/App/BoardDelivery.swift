import Foundation
import MuralKit

/// O que foi lido da área de transferência para colar: música (lida pelo leitor do Música, como no ⌘V), contatos (vCard), a
/// nota do editor de texto ou o resto.
enum ClipboardContent: Sendable {
    case music([MusicDraft])
    case contacts([ContactDraft])
    /// Uma nota do editor de texto, com cartões embutidos e imagens.
    case note(PastedNote)
    case pasted(PasteboardImporter.Content)
}

/// Nenhuma sessão de janela pôde ser obtida para o mural; `message` diz o motivo para a pessoa.
struct SessionRoutingError: LocalizedError, Equatable, Sendable {
    var message: String
    var errorDescription: String? { message }
}

/// Entrega o que foi copiado na raiz de um mural escolhido, esteja ele aberto numa aba, numa aba de fundo ainda não
/// carregada ou fechado.
///
/// Nunca existem duas `BoardWindowSession` do mesmo mural: cada uma grava o mural inteiro, e o salvamento de uma
/// apagaria o cartão da outra. Por isso quem recebe o conteúdo é sempre a sessão que já existe:
/// - mural com aba: a sessão da aba, carregada agora se ainda não estava (o carregamento é de voo único);
/// - mural cuja aba está fechando: espera a sessão dela gravar e fechar, e só então abre uma sessão avulsa;
/// - mural fechado: uma sessão avulsa, que grava, refaz a capa e fecha. Se uma aba for aberta para o mesmo mural
///   enquanto isso, ela adota a sessão avulsa (`adoptDetachedSession(for:)`) e passa a ser a dona.
///
/// As entregas correm numa fila serial, uma por vez, como as capas do `BoardCoverService`.
///
/// O roteamento acima está em `withSession(for:perform:)`, que também serve a quem precisa mexer num mural sem abrir uma
/// segunda sessão dele (a sincronização com o iCloud): tudo o que passa por ali entra na mesma fila.
@MainActor
final class BoardDelivery {
    enum Outcome: Equatable, Sendable {
        case delivered(count: Int)
        case failed(String)
    }

    /// As abas da janela: quem tem a aba de um mural é o dono da sessão dele.
    weak var tabs: MuralTabs?

    /// Um aviso da última entrega que deu certo (uma imagem da nota que não pôde ser colada, por exemplo); `nil` sem aviso.
    private(set) var lastWarning: String?

    private let covers: BoardCoverService?
    private let openSessions: OpenBoardSessions
    private let makeSession: @MainActor (BoardRoute) -> BoardWindowSession
    /// Sessões avulsas, de um mural que não tem aba: do carregamento até a gravação e o fechamento.
    private var detached: [BoardID: BoardWindowSession] = [:]
    /// Fim da fila serial: o trabalho mais recente, que o próximo espera terminar.
    private var lane: Task<Void, Never>?

    /// Quantas vezes se confere o estado do mural antes de desistir: ele muda se a aba fecha (ou reabre) durante a espera.
    private static let maximumAttempts = 3
    private static let nothingToPasteMessage = "Não há nada para colar."
    private static let unreadableMessage = "O conteúdo copiado não pôde virar um cartão."
    private static let unopenedMessage = "O mural não pôde ser aberto."
    private static let closedMessage = "O mural foi fechado antes de receber o conteúdo."
    private static let busyMessage = "O mural estava abrindo e fechando ao mesmo tempo. Tente de novo."
    private static let unsavedMessage = "O cartão entrou no mural, mas a gravação falhou. Abra o mural no app para não perdê-lo."

    /// - Parameters:
    ///   - registry: de onde as sessões avulsas tiram a sessão de domínio do mural.
    ///   - covers: quem refaz a capa de um mural fechado depois da entrega; `nil` não refaz.
    ///   - openSessions: as janelas de mural abertas, para achar a sessão de uma aba que está fechando.
    ///   - makeSession: como se cria a sessão avulsa; os testes trocam. Padrão: `BoardWindowSession(route:registry:)`.
    init(
        registry: BoardSessionRegistry,
        covers: BoardCoverService?,
        openSessions: OpenBoardSessions = .shared,
        makeSession: (@MainActor (BoardRoute) -> BoardWindowSession)? = nil
    ) {
        self.covers = covers
        self.openSessions = openSessions
        self.makeSession = makeSession ?? { BoardWindowSession(route: $0, registry: registry) }
    }

    // MARK: Entrega

    /// Põe o que foi copiado na raiz do mural, no ponto que a pessoa estava olhando.
    /// - Parameter textKind: o tipo de cartão do texto colado; `nil` deixa o classificador escolher.
    func deliver(_ content: ClipboardContent, textKind: ItemKind?, to entry: BoardLibraryEntry) async -> Outcome {
        if case .pasted(.nothing) = content { return .failed(Self.nothingToPasteMessage) }
        let boardID = entry.manifest.id
        do {
            return try await withSession(for: entry.route) { [self] session, isDetached in
                await deliver(content, textKind: textKind, into: session, isDetached: isDetached, boardID: boardID)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Roda `body` com a única sessão de janela do mural, na fila serial das entregas: a da aba (carregada agora se preciso), a
    /// avulsa de uma entrega que já a abriu, ou uma avulsa nova. A avulsa é fechada (gravando) depois de `body`, a não ser que
    /// uma aba a tenha adotado no meio. Se o mural tem uma aba fechando, espera ela gravar e fechar antes.
    ///
    /// Quem chama nunca deve abrir uma `BoardWindowSession` por conta própria, nem gravar o mural pelo `BoardSessionRegistry`:
    /// cada sessão grava o mural inteiro.
    /// - Parameter body: recebe a sessão (com o modelo já carregado) e se ela é avulsa, caso em que a gravação final e o
    ///   fechamento são de quem a abriu.
    /// - Throws: `SessionRoutingError` se nenhuma sessão pôde ser obtida, ou o que `body` lançar. Em qualquer caso a sessão
    ///   avulsa é fechada.
    func withSession<Value: Sendable>(
        for route: BoardRoute,
        perform body: @escaping @MainActor (_ session: BoardWindowSession, _ isDetached: Bool) async throws -> Value
    ) async throws -> Value {
        let result = await serially { [self] () -> Result<Value, any Error> in
            do {
                return .success(try await routed(route, body))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    /// Roda `work` depois de tudo o que entrou na fila antes e antes de tudo o que entrar depois. A fila é só desta instância.
    func serially<Value: Sendable>(_ work: @escaping @MainActor () async -> Value) async -> Value {
        let previous = lane
        let task = Task { @MainActor () -> Value in
            _ = await previous?.value
            return await work()
        }
        let marker = Task { @MainActor in _ = await task.value }
        lane = marker
        let value = await task.value
        if lane == marker { lane = nil }
        return value
    }

    /// Chamado por `MuralTabs` ao criar a aba de um mural: se uma entrega está usando a sessão avulsa dele, a aba fica
    /// com ela, em vez de abrir uma segunda. Devolve a sessão uma vez só; depois disso a aba é a dona e a entrega não a
    /// fecha. `nil` quando não há sessão avulsa viva desse mural.
    func adoptDetachedSession(for route: BoardRoute) -> BoardWindowSession? {
        guard let id = Self.boardID(of: route), let session = detached[id], !session.isClosed else { return nil }
        detached[id] = nil
        return session
    }

    /// A sessão avulsa que uma entrega está usando agora para o mural; os testes conferem por aqui.
    func detachedSession(for id: BoardID) -> BoardWindowSession? {
        detached[id]
    }

    // MARK: Roteamento

    /// Escolhe a sessão do mural e roda `body` nela. O `MuralTabs` tira a aba da lista antes de fechar a sessão: com uma aba
    /// fechando, abrir outra sessão agora gravaria por cima da que ainda está gravando, então espera ela fechar e confere tudo de
    /// novo, porque uma aba pode ter reaberto.
    private func routed<Value: Sendable>(
        _ route: BoardRoute,
        _ body: @MainActor (BoardWindowSession, Bool) async throws -> Value
    ) async throws -> Value {
        guard let id = Self.boardID(of: route) else { throw SessionRoutingError(message: Self.unopenedMessage) }
        for _ in 0..<Self.maximumAttempts {
            if let tab = tabs?.tab(for: id) {
                return try await runInTab(tab.session, body)
            }
            if let closing = closingSession(of: id) {
                await closing.handleWindowWillClose()
                continue
            }
            return try await runInDetachedSession(route, boardID: id, body)
        }
        throw SessionRoutingError(message: Self.busyMessage)
    }

    /// Mural com aba (na frente ou no fundo): usa a sessão dela, que carrega agora se ainda não carregou.
    private func runInTab<Value: Sendable>(
        _ session: BoardWindowSession,
        _ body: @MainActor (BoardWindowSession, Bool) async throws -> Value
    ) async throws -> Value {
        await session.load()
        guard session.model != nil else { throw SessionRoutingError(message: session.error ?? Self.unopenedMessage) }
        return try await body(session, false)
    }

    /// Mural sem aba: abre uma sessão avulsa, roda `body` e fecha.
    ///
    /// A sessão fica em `detached` desde antes de carregar, para uma aba aberta nesse meio-tempo adotá-la. O mapa só
    /// muda de forma síncrona e a sessão só é fechada se ainda estiver nele: com a aba como dona, quem fecha é a aba.
    private func runInDetachedSession<Value: Sendable>(
        _ route: BoardRoute, boardID: BoardID,
        _ body: @MainActor (BoardWindowSession, Bool) async throws -> Value
    ) async throws -> Value {
        let session = makeSession(route)
        detached[boardID] = session
        await session.load()
        guard session.model != nil else {
            let message = session.error ?? Self.unopenedMessage
            await closeIfStillDetached(session, boardID: boardID)
            throw SessionRoutingError(message: message)
        }
        do {
            let value = try await body(session, true)
            await closeIfStillDetached(session, boardID: boardID)
            return value
        } catch {
            await closeIfStillDetached(session, boardID: boardID)
            throw error
        }
    }

    private func closeIfStillDetached(_ session: BoardWindowSession, boardID: BoardID) async {
        guard detached[boardID] === session else { return }
        detached[boardID] = nil
        await session.handleWindowWillClose()
    }

    // MARK: Uma entrega

    /// O corpo de uma entrega, já com a sessão certa. Numa sessão avulsa, grava, refaz a capa e deixa o fechamento para o
    /// roteamento. Sem cartão novo o mural não mudou: a capa gravada continua valendo.
    private func deliver(
        _ content: ClipboardContent, textKind: ItemKind?, into session: BoardWindowSession, isDetached: Bool, boardID: BoardID
    ) async -> Outcome {
        guard let model = session.model else { return .failed(session.error ?? Self.unopenedMessage) }
        var outcome = await apply(content, textKind: textKind, to: session, model: model)
        if case .delivered = outcome { lastWarning = model.lastError } else { lastWarning = nil }
        guard isDetached, case .delivered = outcome else { return outcome }
        // As fotos dos contatos recém-criados precisam estar gravadas (e ligadas aos cartões) antes de a sessão avulsa gravar e fechar.
        await session.contactThumbnails?.waitUntilIdle()
        await session.flushAndPrepareToLeave()
        if session.isDirty {
            // A gravação falhou: o cartão está na sessão de domínio, que o registry guarda (suja) até o mural ser
            // aberto numa aba, que grava de novo ao mudar ou fechar. Sem isso, sair do app o perderia, e dizer
            // "colado" esconderia esse risco.
            outcome = .failed(Self.unsavedMessage)
        } else {
            await refreshCover(of: session, model: model, boardID: boardID)
        }
        return outcome
    }

    /// Refaz a capa do mural com o que acabou de ser gravado, na revisão que ficou no disco.
    private func refreshCover(of session: BoardWindowSession, model: BoardModel, boardID: BoardID) async {
        guard let covers, let domainSession = session.domainSession else { return }
        let revision = await domainSession.manifest.contentRevision
        await covers.refresh(board: model.board, model: model, boardID: boardID, revision: revision)
    }

    /// Uma sessão aberta do mural que não está numa aba nem é a avulsa desta entrega: é uma aba que está fechando.
    private func closingSession(of id: BoardID) -> BoardWindowSession? {
        openSessions.live.first { $0.boardID == id && !$0.isClosed && $0 !== detached[id] }
    }

    // MARK: Aplicar

    /// Põe o conteúdo na raiz do mural, no centro do que a pessoa via (ou onde parou, se a sessão nunca foi mostrada).
    /// Vale o que a sessão criou de fato: nenhum cartão novo é uma falha, com o último erro do modelo como motivo.
    private func apply(
        _ content: ClipboardContent, textKind: ItemKind?, to session: BoardWindowSession, model: BoardModel
    ) async -> Outcome {
        // Uma sessão fechada não grava mais: o cartão ficaria só na memória.
        guard !session.isClosed else { return .failed(Self.closedMessage) }
        let existing = Set(model.board.items.map(\.id))
        model.lastError = nil
        let anchor = session.visibleBoardAnchor ?? session.workspace.canvas.logicalCenter
        switch content {
        case .music(let drafts):
            // `importMusic` da sessão exige o mural na tela; aqui o modelo recebe direto.
            if model.importMusic(drafts.map(\.snapshot), into: nil, at: anchor).isEmpty {
                model.lastError = Self.unreadableMessage
            }
            session.captureBoardIfNeeded()
        case .note(let note):
            if await session.importNote(note, at: anchor) == nil {
                model.lastError = model.lastError ?? Self.unreadableMessage
            }
            session.captureBoardIfNeeded()
        case .contacts(let drafts):
            // Como na música: o modelo recebe direto, e a foto de cada contato é guardada depois.
            let created = model.importContacts(drafts.map(\.snapshot), into: nil, at: anchor)
            if created.isEmpty {
                model.lastError = Self.unreadableMessage
            } else {
                session.contactThumbnailStore()?.store(drafts, for: created)
            }
            session.captureBoardIfNeeded()
        case .pasted(.nothing):
            return .failed(Self.nothingToPasteMessage)
        case .pasted(.text(let text)):
            let paste = PendingPaste(text: text, folderID: nil, anchor: anchor)
            session.importPastedText(paste, as: textKind ?? ContentClassifier.kind(forText: text))
        case .pasted(let other):
            await session.importPasted(other, into: nil, anchor: anchor, animation: nil)
        }
        let count = model.board.items.count { !existing.contains($0.id) }
        return count > 0 ? .delivered(count: count) : .failed(model.lastError ?? Self.unreadableMessage)
    }

    private static func boardID(of route: BoardRoute) -> BoardID? {
        switch route {
        case .library: nil
        case .welcomeDraft(let id), .saved(let id): id
        }
    }
}
