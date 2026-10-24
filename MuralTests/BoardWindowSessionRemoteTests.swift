import Foundation
import MuralKit
import MuralSync
import Testing

@testable import Mural

/// A sessão de janela recebe o que chegou do iCloud (`applyRemote`) sem perder o que a pessoa está fazendo. O iCloud não entra: cada
/// teste monta o `ReceivedChanges` à mão, com a base como o iCloud a conheceria.
@Suite("Sessão de janela: receber do iCloud")
@MainActor
struct BoardWindowSessionRemoteTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralSessionRemote-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor
    private struct Scene {
        let directory: URL
        let library: BoardLibrary
        let route: BoardRoute
        let session: BoardWindowSession
        var model: BoardModel { session.model! }
    }

    /// Um mural com uma nota (`.text`, não post-it) por texto, já gravado no disco e com a sessão carregada.
    private func makeScene(_ texts: [String] = [], name: String = "Original") async throws -> (scene: Scene, notes: [BoardItem]) {
        let directory = try root()
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard(name)
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library), usesOnDeviceModel: false)
        await session.load()
        let scene = Scene(directory: directory, library: library, route: route, session: session)
        let notes = try texts.map { try #require(scene.model.importText($0, as: .text)) }
        session.captureBoardIfNeeded()
        await session.flushAndPrepareToLeave()
        #expect(!session.isDirty)
        return (scene, notes)
    }

    /// O mural como o iCloud o conhece: os cartões na forma compartilhada.
    private func synced(_ board: Board) -> Board {
        var base = board
        base.items = base.items.map(SharedFieldPolicy.shared)
        return base
    }

    private func received(
        _ changes: RemoteBoardChanges, base: Board, name: String? = nil, previousBaseName: String? = nil
    ) -> ReceivedChanges {
        ReceivedChanges(changes: changes, previousBase: base, name: name, previousBaseName: previousBaseName)
    }

    private func edited(_ item: BoardItem, text: String) -> BoardItem {
        var remote = SharedFieldPolicy.shared(item)
        remote.text = text
        return remote
    }

    private func diskBoard(_ scene: Scene) async throws -> Board {
        try #require(await scene.library.open(scene.route)).board
    }

    @MainActor
    private final class PersistRecorder {
        private(set) var events: [(board: Board, fromRemote: Bool)] = []
        func record(_ board: Board, _ fromRemote: Bool) { events.append((board, fromRemote)) }
    }

    // MARK: Mudança remota

    @Test("Cartão novo, editado e apagado chegam ao mural e ao disco antes de applyRemote voltar")
    func remoteChangesAreInTheBoardAndOnDisk() async throws {
        let (scene, notes) = try await makeScene(["um", "dois", "três"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let (first, second, third) = (notes[0], notes[1], notes[2])
        let base = synced(scene.model.board)
        let arrival = BoardItem(kind: .text, title: "Novo", createdAt: .now, position: BoardPoint(x: 400, y: 400), text: "chegou")

        try await scene.session.applyRemote(
            received(
                RemoteBoardChanges(
                    savedItems: [edited(first, text: "um editado lá"), arrival], deletedItemIDs: [third.id]), base: base))

        let board = scene.model.board
        #expect(board.item(id: first.id)?.text == "um editado lá")
        #expect(board.item(id: second.id)?.text == "dois")
        #expect(board.item(id: third.id) == nil)
        #expect(board.item(id: arrival.id)?.text == "chegou")

        let disk = try await diskBoard(scene)
        #expect(disk.item(id: first.id)?.text == "um editado lá")
        #expect(disk.item(id: third.id) == nil)
        #expect(disk.item(id: arrival.id)?.text == "chegou")
        #expect(!scene.session.isDirty)
        #expect(scene.session.lastPersistedBoard?.item(id: arrival.id)?.text == "chegou")
    }

    @Test("Sem aba carregada ou com a janela fechada, applyRemote recusa")
    func unavailableSessionRefuses() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Sem carga")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library), usesOnDeviceModel: false)

        await #expect(throws: BoardSyncApplyError.unavailable) {
            try await session.applyRemote(ReceivedChanges())
        }
    }

    @Test("Num mural só para ver a mudança remota entra do mesmo jeito")
    func readOnlyBoardReceivesRemoteChanges() async throws {
        let (scene, notes) = try await makeScene(["um"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        scene.model.isReadOnly = true
        let base = synced(scene.model.board)

        try await scene.session.applyRemote(
            received(RemoteBoardChanges(savedItems: [edited(notes[0], text: "mudado por quem edita")]), base: base))

        #expect(scene.model.board.item(id: notes[0].id)?.text == "mudado por quem edita")
        #expect(try await diskBoard(scene).item(id: notes[0].id)?.text == "mudado por quem edita")
    }

    // MARK: Último mural gravado

    @Test("Edição local não gravada fica fora de lastPersistedBoard até a gravação")
    func lastPersistedBoardFollowsOnlyFlushes() async throws {
        let (scene, notes) = try await makeScene(["base"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        #expect(scene.session.lastPersistedBoard == scene.model.board, "ao carregar e gravar, é o mural gravado")

        let local = try #require(scene.model.importText("só aqui"))
        scene.session.captureBoardIfNeeded()
        #expect(scene.model.board.item(id: local.id) != nil)
        #expect(scene.session.lastPersistedBoard?.item(id: local.id) == nil, "capturada, mas ainda não gravada")
        #expect(scene.session.lastPersistedBoard?.item(id: notes[0].id) != nil)

        await scene.session.flushAndPrepareToLeave()
        #expect(scene.session.lastPersistedBoard?.item(id: local.id)?.text == "só aqui")
        #expect(scene.session.lastPersistedBoard == scene.model.board)
    }

    // MARK: Rascunhos

    private let threeParagraphs = "Parágrafo um\n\nParágrafo dois\n\nParágrafo três"

    @Test("Rascunho de nota aberto e mudança remota em outro parágrafo: o rascunho fica com as duas")
    func draftKeepsBothEditsInDifferentParagraphs() async throws {
        let (scene, notes) = try await makeScene([threeParagraphs])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let note = notes[0]
        let base = synced(scene.model.board)
        scene.session.beginEditing(note.id)
        var draft = NoteDraft(item: note)
        draft.text = "Parágrafo um editado aqui\n\nParágrafo dois\n\nParágrafo três"
        scene.session.setNoteDraft(draft, for: note.id)

        try await scene.session.applyRemote(
            received(
                RemoteBoardChanges(savedItems: [edited(note, text: "Parágrafo um\n\nParágrafo dois\n\nParágrafo três editado lá")]),
                base: base))

        let joined = "Parágrafo um editado aqui\n\nParágrafo dois\n\nParágrafo três editado lá"
        #expect(scene.session.noteDrafts[note.id]?.text == joined)
        #expect(scene.session.editingItemID == note.id, "a edição continua aberta")
        #expect(scene.model.board.items.count == 1, "juntou sem cópia")
        #expect(scene.model.board.item(id: note.id)?.text == "Parágrafo um\n\nParágrafo dois\n\nParágrafo três editado lá")

        // Ao concluir a edição, o cartão fica com as duas.
        scene.session.commitNoteDrafts()
        #expect(scene.model.board.item(id: note.id)?.text == joined)
    }

    @Test("Rascunho de nota e mudança remota na mesma linha: o rascunho fica e nasce a cópia com a versão que chegou")
    func draftStaysAndRemoteVersionBecomesACopy() async throws {
        let (scene, notes) = try await makeScene([threeParagraphs])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let note = notes[0]
        let base = synced(scene.model.board)
        var draft = NoteDraft(item: note)
        draft.text = "Parágrafo um\n\nParágrafo dois, o meu\n\nParágrafo três"
        scene.session.setNoteDraft(draft, for: note.id)
        let remoteText = "Parágrafo um\n\nParágrafo dois, o deles\n\nParágrafo três"

        try await scene.session.applyRemote(received(RemoteBoardChanges(savedItems: [edited(note, text: remoteText)]), base: base))

        #expect(scene.session.noteDrafts[note.id] == draft, "o texto sob o cursor não muda")
        let board = scene.model.board
        #expect(board.items.count == 2)
        #expect(board.item(id: note.id)?.text == remoteText, "o cartão guarda o que chegou até a pessoa concluir")
        let copy = try #require(board.items.first { $0.id != note.id })
        #expect(copy.text == remoteText)
        #expect(copy.title.hasSuffix("(cópia de conflito)"))
        #expect(try await diskBoard(scene).item(id: copy.id)?.text == remoteText)

        // Concluída a edição, o cartão fica com o que a pessoa escreveu e a versão que chegou segue na cópia.
        scene.session.commitNoteDrafts()
        #expect(scene.model.board.item(id: note.id)?.text == draft.text)
        #expect(scene.model.board.item(id: copy.id)?.text == remoteText)
    }

    @Test("Cartão com rascunho apagado por outra pessoa volta como cópia com o texto do rascunho")
    func deletedCardWithDraftBecomesACopy() async throws {
        let (scene, notes) = try await makeScene(["original", "outro"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let note = notes[0]
        let base = synced(scene.model.board)
        scene.session.beginEditing(note.id)
        var draft = NoteDraft(item: note)
        draft.text = "original, mais o que digitei"
        scene.session.setNoteDraft(draft, for: note.id)

        try await scene.session.applyRemote(received(RemoteBoardChanges(deletedItemIDs: [note.id]), base: base))

        let board = scene.model.board
        #expect(board.item(id: note.id) == nil)
        let copy = try #require(board.items.first { $0.text == "original, mais o que digitei" })
        #expect(copy.id != note.id)
        #expect(scene.session.noteDrafts[note.id] == nil, "o rascunho saiu: o texto está na cópia")
        #expect(scene.session.editingItemID == nil, "o editor fecha como em qualquer cartão apagado")
        #expect(board.item(id: notes[1].id) != nil)
        #expect(try await diskBoard(scene).item(id: copy.id)?.text == "original, mais o que digitei")
    }

    @Test("Rascunho igual ao cartão apagado não tem o que proteger e não gera cópia")
    func untouchedDraftOfADeletedCardLeavesNoCopy() async throws {
        let (scene, notes) = try await makeScene(["original"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let base = synced(scene.model.board)
        scene.session.beginEditing(notes[0].id)
        scene.session.setNoteDraft(NoteDraft(item: notes[0]), for: notes[0].id)

        try await scene.session.applyRemote(received(RemoteBoardChanges(deletedItemIDs: [notes[0].id]), base: base))

        #expect(scene.model.board.items.isEmpty)
        #expect(scene.session.noteDrafts[notes[0].id] == nil)
        #expect(scene.session.editingItemID == nil)
    }

    @Test("Título que a pessoa não mexeu acompanha o que chegou; o que ela mexeu fica")
    func untouchedTitleFollowsTheRemoteOne() async throws {
        let (scene, notes) = try await makeScene(["um", "dois"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let (first, second) = (notes[0], notes[1])
        let base = synced(scene.model.board)
        scene.session.setNoteDraft(NoteDraft(item: first), for: first.id)
        var mine = NoteDraft(item: second)
        mine.title = "Meu título"
        scene.session.setNoteDraft(mine, for: second.id)
        var retitledFirst = SharedFieldPolicy.shared(first)
        retitledFirst.title = "Título de lá"
        var retitledSecond = SharedFieldPolicy.shared(second)
        retitledSecond.title = "Outro título de lá"

        try await scene.session.applyRemote(
            received(RemoteBoardChanges(savedItems: [retitledFirst, retitledSecond]), base: base))

        #expect(scene.session.noteDrafts[first.id]?.title == "Título de lá")
        #expect(scene.session.noteDrafts[second.id]?.title == "Meu título")
    }

    @Test("Post-it com rascunho: o texto junta por linha, a cor que a pessoa não mexeu acompanha e a colisão não marca o título")
    func stickyDraftMergesAndFollowsColor() async throws {
        let (scene, _) = try await makeScene()
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let sticky = try #require(scene.model.importText("Comprar pão\nComprar leite\nComprar café", as: .sticky))
        scene.session.captureBoardIfNeeded()
        await scene.session.flushAndPrepareToLeave()
        let base = synced(scene.model.board)
        var draft = NoteDraft(item: sticky)
        draft.text = "Comprar pão integral\nComprar leite\nComprar café"
        scene.session.setNoteDraft(draft, for: sticky.id)
        var remote = SharedFieldPolicy.shared(sticky)
        remote.text = "Comprar pão\nComprar leite\nComprar café e chá"
        remote.title = "Comprar pão"
        remote.stickyColor = .blue

        try await scene.session.applyRemote(received(RemoteBoardChanges(savedItems: [remote]), base: base))

        let joined = scene.session.noteDrafts[sticky.id]
        #expect(joined?.text == "Comprar pão integral\nComprar leite\nComprar café e chá")
        #expect(joined?.color == .blue)
        #expect(scene.model.board.items.count == 1)

        // Colisão na mesma linha: o post-it fica com a versão que chegou e a cópia, sem sufixo no título, também.
        var colliding = NoteDraft(item: try #require(scene.model.item(id: sticky.id)))
        colliding.text = "Comprar pão de forma\nComprar leite\nComprar café e chá"
        scene.session.setNoteDraft(colliding, for: sticky.id)
        let current = synced(scene.model.board)
        var again = SharedFieldPolicy.shared(try #require(scene.model.item(id: sticky.id)))
        again.text = "Comprar pão doce\nComprar leite\nComprar café e chá"
        again.title = "Comprar pão doce"

        try await scene.session.applyRemote(received(RemoteBoardChanges(savedItems: [again]), base: current))

        #expect(scene.session.noteDrafts[sticky.id] == colliding)
        let copy = try #require(scene.model.board.items.first { $0.id != sticky.id })
        #expect(copy.text == again.text)
        #expect(copy.title == again.title)
    }

    @Test("Legenda com rascunho: igual à de antes acompanha o que chegou; em colisão fica e a versão que chegou vira cópia")
    func captionDraftsFollowOrCollide() async throws {
        let (scene, _) = try await makeScene()
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let followed = try #require(
            scene.model.importData(Data([1]), fileExtension: "png", kind: .image, title: "Segue"))
        let collided = try #require(
            scene.model.importData(Data([2]), fileExtension: "png", kind: .image, title: "Colide"))
        scene.model.setCaption("Praia", for: followed.id)
        scene.model.setCaption("Praia", for: collided.id)
        scene.session.captureBoardIfNeeded()
        await scene.session.flushAndPrepareToLeave()
        let base = synced(scene.model.board)
        scene.session.setCaptionDraft("Praia", for: followed.id)
        scene.session.setCaptionDraft("Praia de manhã", for: collided.id)
        var remoteFollowed = SharedFieldPolicy.shared(try #require(scene.model.item(id: followed.id)))
        remoteFollowed.caption = "Praia deserta"
        var remoteCollided = SharedFieldPolicy.shared(try #require(scene.model.item(id: collided.id)))
        remoteCollided.caption = "Praia ao pôr do sol"

        try await scene.session.applyRemote(
            received(RemoteBoardChanges(savedItems: [remoteFollowed, remoteCollided]), base: base))

        #expect(scene.session.captionDrafts[followed.id] == "Praia deserta")
        #expect(scene.session.captionDrafts[collided.id] == "Praia de manhã")
        let copies = scene.model.board.items.filter { $0.id != followed.id && $0.id != collided.id }
        #expect(copies.count == 1)
        #expect(copies.first?.caption == "Praia ao pôr do sol")
    }

    // MARK: Nome

    @Test("O nome que chegou vale quando o daqui é o da base")
    func remoteNameIsAppliedWhenLocalIsTheBase() async throws {
        let (scene, _) = try await makeScene(name: "Original")
        defer { try? FileManager.default.removeItem(at: scene.directory) }

        try await scene.session.applyRemote(
            received(RemoteBoardChanges(), base: synced(scene.model.board), name: "Nome de lá", previousBaseName: "Original"))

        #expect(scene.session.manifestName == "Nome de lá")
        #expect(try await scene.library.open(scene.route)?.manifest.name == "Nome de lá")
        #expect(!scene.session.isDirty)
    }

    @Test("O nome daqui fica quando foi renomeado aqui desde a base")
    func localNameStaysWhenRenamedHere() async throws {
        let (scene, _) = try await makeScene(name: "Original")
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        await scene.session.rename(to: "Meu nome")

        try await scene.session.applyRemote(
            received(RemoteBoardChanges(), base: synced(scene.model.board), name: "Nome de lá", previousBaseName: "Original"))

        #expect(scene.session.manifestName == "Meu nome")
        #expect(try await scene.library.open(scene.route)?.manifest.name == "Meu nome")
    }

    // MARK: Falha de gravação

    @Test("Se a gravação falha, applyRemote lança, o disco e o último gravado ficam como estavam e a retentativa grava")
    func failedFlushThrows() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let initialLibrary = BoardLibrary(rootDirectory: directory)
        let route = try await initialLibrary.createNamedBoard("Falha")
        let failingLibrary = BoardLibrary(
            rootDirectory: directory, repositoryFaultInjection: BoardRepositoryFaultInjection(points: [.beforeSwap]))
        let session = BoardWindowSession(
            route: route, registry: BoardSessionRegistry(library: failingLibrary), usesOnDeviceModel: false)
        await session.load()
        let model = try #require(session.model)
        let recorder = PersistRecorder()
        session.onPersisted = { recorder.record($0, $1) }
        let before = model.board
        let arrival = BoardItem(kind: .text, title: "Chegou", createdAt: .now, position: BoardPoint(x: 100, y: 100), text: "de lá")

        do {
            try await session.applyRemote(received(RemoteBoardChanges(savedItems: [arrival]), base: synced(before)))
            Issue.record("applyRemote devia lançar com a gravação falhando")
        } catch let failure as BoardSyncApplyError {
            guard case .saveFailed = failure else {
                Issue.record("esperava saveFailed, veio \(failure)")
                return
            }
            #expect(failure.errorDescription?.contains("não pôde ser gravado") == true)
        }

        #expect(session.isDirty)
        #expect(session.error?.contains("Não foi possível salvar o mural:") == true)
        #expect(session.lastPersistedBoard == before)
        #expect(recorder.events.isEmpty)
        #expect(try #require(await failingLibrary.open(route)).board.item(id: arrival.id) == nil)

        // O mural junto continua em memória e a próxima gravação o leva ao disco.
        await session.flushAndPrepareToLeave()
        #expect(!session.isDirty)
        #expect(try #require(await failingLibrary.open(route)).board.item(id: arrival.id)?.text == "de lá")
    }

    // MARK: Fila

    @Test("Gravação e renomeação na fila junto com applyRemote terminam sem travar e sem perder nada", .timeLimit(.minutes(1)))
    func queuedWorkTogetherWithApplyRemoteFinishes() async throws {
        let (scene, notes) = try await makeScene(["um"], name: "Original")
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let base = synced(scene.model.board)
        let local = try #require(scene.model.importText("daqui", as: .text))
        scene.session.captureBoardIfNeeded()
        let flush = Task { await scene.session.flushAndPrepareToLeave() }
        let rename = Task { await scene.session.rename(to: "Meu nome") }

        try await scene.session.applyRemote(
            received(
                RemoteBoardChanges(savedItems: [edited(notes[0], text: "um, de lá")]), base: base, name: "Nome de lá",
                previousBaseName: "Original"))
        await flush.value
        await rename.value

        #expect(!scene.session.isDirty)
        #expect(scene.session.manifestName == "Meu nome", "renomeado aqui, o nome daqui vale em qualquer ordem da fila")
        let disk = try await diskBoard(scene)
        #expect(disk.item(id: local.id)?.text == "daqui")
        #expect(disk.item(id: notes[0].id)?.text == "um, de lá")
        #expect(try await scene.library.open(scene.route)?.manifest.name == "Meu nome")
    }

    // MARK: Aviso depois da gravação

    @Test("onPersisted chega com fromRemote verdadeiro depois de applyRemote e falso depois de uma edição local")
    func onPersistedTellsWhereTheFlushCameFrom() async throws {
        let (scene, notes) = try await makeScene(["um"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let recorder = PersistRecorder()
        scene.session.onPersisted = { recorder.record($0, $1) }

        try await scene.session.applyRemote(
            received(
                RemoteBoardChanges(savedItems: [edited(notes[0], text: "um, de lá")]), base: synced(scene.model.board)))
        #expect(recorder.events.count == 1)
        #expect(recorder.events.last?.fromRemote == true)
        #expect(recorder.events.last?.board.item(id: notes[0].id)?.text == "um, de lá")

        let local = try #require(scene.model.importText("daqui"))
        scene.session.captureBoardIfNeeded()
        await scene.session.flushAndPrepareToLeave()
        #expect(recorder.events.count == 2)
        #expect(recorder.events.last?.fromRemote == false)
        #expect(recorder.events.last?.board.item(id: local.id)?.text == "daqui")
    }

    @Test("Edição local e junção na mesma volta da fila: uma gravação só, com as duas, e fromRemote falso")
    func localEditAndMergeInTheSameFlushIsNotFromRemote() async throws {
        let (scene, notes) = try await makeScene(["um"])
        defer { try? FileManager.default.removeItem(at: scene.directory) }
        let base = synced(scene.model.board)
        let recorder = PersistRecorder()
        scene.session.onPersisted = { recorder.record($0, $1) }
        let arrival = BoardItem(kind: .text, title: "Chegou", createdAt: .now, position: BoardPoint(x: 500, y: 500), text: "de lá")

        // Edição local capturada e ainda não gravada quando a junção entra.
        let local = try #require(scene.model.importText("daqui"))
        scene.session.captureBoardIfNeeded()
        try await scene.session.applyRemote(received(RemoteBoardChanges(savedItems: [arrival]), base: base))

        #expect(recorder.events.count == 1)
        #expect(recorder.events.last?.fromRemote == false, "há edição local a enviar")
        let persisted = try #require(recorder.events.last?.board)
        #expect(persisted.item(id: local.id)?.text == "daqui")
        #expect(persisted.item(id: arrival.id)?.text == "de lá")
        #expect(persisted.item(id: notes[0].id) != nil)
        #expect(try await diskBoard(scene).items.map(\.id) == persisted.items.map(\.id))
    }
}
