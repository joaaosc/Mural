import Foundation
import MuralKit

/// O que foi lido da área de transferência para colar: música (lida pelo leitor do Música, como no ⌘V) ou o resto.
enum ClipboardContent: Sendable {
    case music([MusicDraft])
    case pasted(PasteboardImporter.Content)
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
@MainActor
final class BoardDelivery {
    enum Outcome: Equatable, Sendable {
        case delivered(count: Int)
        case failed(String)
    }

    /// As abas da janela: quem tem a aba de um mural é o dono da sessão dele.
    weak var tabs: MuralTabs?

    private let covers: BoardCoverService?
    private let openSessions: OpenBoardSessions
    private let makeSession: @MainActor (BoardRoute) -> BoardWindowSession
    /// Sessões avulsas, de um mural que não tem aba: do carregamento até a gravação e o fechamento.
    private var detached: [BoardID: BoardWindowSession] = [:]
    /// Fim da fila serial: a entrega mais recente, que a próxima espera terminar.
    private var lane: Task<Outcome, Never>?

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
        let previous = lane
        let task = Task { @MainActor [self] () -> Outcome in
            _ = await previous?.value
            return await perform(content, textKind: textKind, to: entry)
        }
        lane = task
        let outcome = await task.value
        if lane == task { lane = nil }
        return outcome
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

    // MARK: Uma entrega

    private func perform(_ content: ClipboardContent, textKind: ItemKind?, to entry: BoardLibraryEntry) async -> Outcome {
        if case .pasted(.nothing) = content { return .failed(Self.nothingToPasteMessage) }
        let id = entry.manifest.id
        for _ in 0..<Self.maximumAttempts {
            if let tab = tabs?.tab(for: id) {
                return await deliverToTab(content, textKind: textKind, session: tab.session)
            }
            // O `MuralTabs` tira a aba da lista antes de fechar a sessão. Abrir outra agora gravaria por cima da que
            // ainda está gravando: espera ela fechar e confere tudo de novo, porque uma aba pode ter reaberto.
            if let closing = closingSession(of: id) {
                await closing.handleWindowWillClose()
                continue
            }
            return await deliverToDetachedSession(content, textKind: textKind, entry: entry)
        }
        return .failed(Self.busyMessage)
    }

    /// Mural com aba (na frente ou no fundo): entrega na sessão dela, que carrega agora se ainda não carregou.
    private func deliverToTab(_ content: ClipboardContent, textKind: ItemKind?, session: BoardWindowSession) async -> Outcome {
        await session.load()
        guard let model = session.model else { return .failed(session.error ?? Self.unopenedMessage) }
        return await apply(content, textKind: textKind, to: session, model: model)
    }

    /// Mural sem aba: abre uma sessão avulsa, entrega, grava, refaz a capa e fecha.
    ///
    /// A sessão fica em `detached` desde antes de carregar, para uma aba aberta nesse meio-tempo adotá-la. O mapa só
    /// muda de forma síncrona e a sessão só é fechada se ainda estiver nele: com a aba como dona, quem fecha é a aba.
    private func deliverToDetachedSession(
        _ content: ClipboardContent, textKind: ItemKind?, entry: BoardLibraryEntry
    ) async -> Outcome {
        let id = entry.manifest.id
        let session = makeSession(entry.route)
        detached[id] = session
        await session.load()
        guard let model = session.model else {
            let message = session.error ?? Self.unopenedMessage
            await closeIfStillDetached(session, boardID: id)
            return .failed(message)
        }
        var outcome = await apply(content, textKind: textKind, to: session, model: model)
        // Sem cartão novo o mural não mudou: a capa gravada continua valendo.
        if case .delivered = outcome {
            await session.flushAndPrepareToLeave()
            if session.isDirty {
                // A gravação falhou: o cartão está na sessão de domínio, que o registry guarda (suja) até o mural ser
                // aberto numa aba, que grava de novo ao mudar ou fechar. Sem isso, sair do app o perderia, e dizer
                // "colado" esconderia esse risco.
                outcome = .failed(Self.unsavedMessage)
            } else {
                await refreshCover(of: session, model: model, boardID: id)
            }
        }
        await closeIfStillDetached(session, boardID: id)
        return outcome
    }

    private func closeIfStillDetached(_ session: BoardWindowSession, boardID: BoardID) async {
        guard detached[boardID] === session else { return }
        detached[boardID] = nil
        await session.handleWindowWillClose()
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
