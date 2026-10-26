import Foundation
import MuralKit
import MuralSync
import Testing

@Suite("iCloud: o coordenador da sincronização dos murais")
struct BoardSyncCoordinatorTests {
    private static let imageFile = "AAAAAAAA-0000-4000-8000-000000000001.jpg"

    // MARK: Ajudantes

    /// Um Mac com um mural: o host de teste, a loja em disco e o coordenador.
    private struct Setup {
        let root: URL
        let boardID: BoardID
        let zone: CloudZoneID
        let host: SyncTestHost
        let store: SyncMetadataStore
        let coordinator: BoardSyncCoordinator

        var items: URL { root.appendingPathComponent("Items", isDirectory: true) }
        var syncDirectory: URL { root.appendingPathComponent("Sync", isDirectory: true) }
        var cloud: BoardCloudInfo {
            BoardCloudInfo(database: .private, zoneName: zone.name, zoneOwnerName: zone.ownerName, permission: .owner)
        }

        func recordID(_ name: String) -> CloudRecordID {
            CloudRecordID(zone: zone, name: name)
        }

        func recordID(_ item: BoardItem) -> CloudRecordID {
            recordID(item.id.uuidString)
        }

        func saves(_ names: [String]) -> Set<PendingChange> {
            Set(names.map { PendingChange.save(recordID($0)) })
        }

        func deletes(_ names: [String]) -> Set<PendingChange> {
            Set(names.map { PendingChange.delete(recordID($0)) })
        }
    }

    /// - Parameter hasLocalBoard: `false` deixa o Mac sem o pacote do mural, para o coordenador adotar a zona; o host o cria em `Items/`.
    private func makeSetup(
        board: Board = Board(), name: String = "Casa", files: [String] = [], scope: CloudDatabaseScope = .private,
        hasLocalBoard: Bool = true
    ) async throws -> Setup {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralSyncCoordinator-\(UUID().uuidString)", isDirectory: true)
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        for file in files { try Data("conteúdo de \(file)".utf8).write(to: items.appendingPathComponent(file)) }
        let boardID = BoardID()
        let host = SyncTestHost(adoptedItemsDirectory: items)
        if hasLocalBoard { await host.add(boardID, name: name, board: board, itemsDirectory: items) }
        let store = SyncMetadataStore(directory: root.appendingPathComponent("Sync", isDirectory: true))
        return Setup(
            root: root, boardID: boardID, zone: CloudZoneID(name: CloudSchema.zoneName(for: boardID)), host: host, store: store,
            coordinator: BoardSyncCoordinator(scope: scope, store: store, host: host))
    }

    /// Um mural já enviado: o iCloud aceitou tudo e nada está pendente.
    private func syncedSetup(board: Board, files: [String] = []) async throws -> Setup {
        let setup = try await makeSetup(board: board, files: files)
        let pending = try await setup.coordinator.startTracking(setup.boardID, cloud: setup.cloud)
        let remaining = try await accept(pending, in: setup)
        try #require(remaining.isEmpty, "o envio inicial deixou \(remaining.count) pendências")
        return setup
    }

    private func cleanUp(_ setup: Setup) {
        try? FileManager.default.removeItem(at: setup.root)
    }

    /// O registro que o motor enviaria, com a marca de alteração que o iCloud daria.
    private func sentRecord(_ id: CloudRecordID, in setup: Setup, tag: String = "v1") async throws -> CloudRecord {
        var record = try #require(
            try await setup.coordinator.record(for: id), "o registro \(id.name) é pendente, mas não pôde ser montado")
        record.systemFields = Data("\(tag):\(id.name)".utf8)
        return record
    }

    /// O iCloud aceita tudo o que está pendente, com uma marca de alteração nova em cada registro.
    @discardableResult
    private func accept(_ pending: Set<PendingChange>, in setup: Setup, tag: String = "v1") async throws -> Set<PendingChange> {
        var saved: [CloudRecord] = []
        var deleted: [CloudRecordID] = []
        for change in pending {
            switch change {
            case .save(let id): saved.append(try await sentRecord(id, in: setup, tag: tag))
            case .delete(let id): deleted.append(id)
            }
        }
        return try await setup.coordinator.handleSent(saved: saved, deleted: deleted, failures: [])
    }

    /// O registro de um cartão como o iCloud o devolveria, com a marca de alteração do servidor.
    private func serverCard(_ item: BoardItem, layer: Double, mark: String, in setup: Setup) throws -> CloudRecord {
        CloudRecord(
            id: setup.recordID(item), type: "Card", fields: try CardRecordMapping.fields(for: item, layer: layer),
            creatorUserRecordName: "dono", systemFields: Data(mark.utf8))
    }

    /// O registro do mural como o iCloud o devolveria.
    private func serverBoard(name: String, formatVersion: Int, mark: String, in setup: Setup) -> CloudRecord {
        CloudRecord(
            id: setup.recordID(CloudSchema.muralRecordName), type: "Mural",
            fields: ["name": .string(name), "formatVersion": .int(Int64(formatVersion))], creatorUserRecordName: "dono",
            systemFields: Data(mark.utf8))
    }

    private func makeNote(_ title: String = "Nota", text: String = "Texto", x: Double = 10) -> BoardItem {
        BoardItem(
            kind: .text, title: title, createdAt: SyncFixtures.fractionalDate, position: BoardPoint(x: x, y: 20), text: text)
    }

    private func edit(_ setup: Setup, _ change: (inout Board) -> Void) async {
        var board = await setup.host.board(setup.boardID)
        change(&board)
        await setup.host.write(board, for: setup.boardID)
    }

    private func storedState(_ setup: Setup) async throws -> BoardSyncState {
        try #require(try await setup.store.state(for: setup.boardID), "o estado do mural não está gravado")
    }

    // MARK: Murais acompanhados

    @Test("Cada coordenador lista só os murais do seu banco e não aceita acompanhar um mural de outro banco")
    func boardIDsAreScopedToTheDatabase() async throws {
        let setup = try await makeSetup()
        defer { cleanUp(setup) }
        let sharedID = BoardID()
        let sharedInfo = BoardCloudInfo(
            database: .shared, zoneName: CloudSchema.zoneName(for: sharedID), zoneOwnerName: "dono", ownerDisplayName: "Ana",
            permission: .readWrite)
        _ = try await setup.coordinator.startTracking(setup.boardID, cloud: setup.cloud)
        try await setup.store.save(BoardSyncState(cloud: sharedInfo), for: sharedID)
        let sharedCoordinator = BoardSyncCoordinator(scope: .shared, store: setup.store, host: setup.host)

        #expect(try await setup.coordinator.boardIDs() == [setup.boardID])
        #expect(try await sharedCoordinator.boardIDs() == [sharedID])
        await #expect(throws: BoardSyncCoordinatorError.wrongDatabase(sharedID)) {
            _ = try await setup.coordinator.startTracking(sharedID, cloud: sharedInfo)
        }
        #expect(try await setup.store.state(for: sharedID)?.cloud == sharedInfo, "o estado do outro banco não é tocado")
    }

    @Test("Acompanhar um mural pela primeira vez deixa tudo pendente (base vazia) e grava o estado; acompanhar de novo mantém a base")
    func startTrackingStartsFromAnEmptyBase() async throws {
        let folder = BoardItem(kind: .folder, title: "Pasta", createdAt: SyncFixtures.fractionalDate)
        let image = BoardItem(
            kind: .image, title: "Foto", createdAt: SyncFixtures.otherFractionalDate, position: BoardPoint(x: 50, y: 50),
            fileName: Self.imageFile)
        let freeText = BoardFreeText(text: "Oi", createdAt: SyncFixtures.fractionalDate)
        let setup = try await makeSetup(board: Board(items: [folder, image], freeTexts: [freeText]), files: [Self.imageFile])
        defer { cleanUp(setup) }

        let pending = try await setup.coordinator.startTracking(setup.boardID, cloud: setup.cloud)

        let everything = [folder.id.uuidString, image.id.uuidString, freeText.id.uuidString, "mural", Self.imageFile]
        #expect(pending == setup.saves(everything))
        let first = try await storedState(setup)
        #expect(first.cloud == setup.cloud && first.base.items.isEmpty && first.baseName == nil)

        try await accept(pending, in: setup)
        var downgraded = setup.cloud
        downgraded.permission = .readOnly
        #expect(try await setup.coordinator.startTracking(setup.boardID, cloud: downgraded).isEmpty, "a base não se perde")
        let again = try await storedState(setup)
        #expect(again.cloud.permission == .readOnly && again.base.items.count == 2)
    }

    @Test("Parar de acompanhar apaga o estado: nada fica pendente e os registros do mural deixam de ser montados")
    func stopTrackingForgetsTheBoard() async throws {
        let note = makeNote()
        let setup = try await syncedSetup(board: Board(items: [note]))
        defer { cleanUp(setup) }

        try await setup.coordinator.stopTracking(setup.boardID)

        #expect(try await setup.store.state(for: setup.boardID) == nil)
        #expect(try await setup.coordinator.boardIDs().isEmpty)
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
        #expect(try await setup.coordinator.record(for: setup.recordID(note)) == nil)
    }

    @Test("Registros de uma zona desconhecida (que não é de mural, ou de um mural não acompanhado) são ignorados em todo evento")
    func unknownZonesAreIgnored() async throws {
        let setup = try await syncedSetup(board: Board(items: [makeNote()]))
        defer { cleanUp(setup) }
        let strangers = [CloudZoneID(name: "Outra"), CloudZoneID(name: CloudSchema.zoneName(for: BoardID()))]

        for zone in strangers {
            let id = CloudRecordID(zone: zone, name: UUID().uuidString)
            let record = CloudRecord(
                id: id, type: "Card", fields: try CardRecordMapping.fields(for: makeNote(), layer: 1), systemFields: Data("x".utf8))
            #expect(try await setup.coordinator.handleFetched(saved: [record], deleted: [id]).isEmpty)
            let failures: [SyncSaveFailure] = [.permission(id), .zoneMissing(zone), .conflict(serverRecord: record)]
            #expect(try await setup.coordinator.handleSent(saved: [record], deleted: [id], failures: failures).isEmpty)
            try await setup.coordinator.handleZoneDeleted(zone, reason: .zoneDeleted)
            #expect(try await setup.coordinator.record(for: id) == nil)
        }

        let received = await setup.host.received
        let removals = await setup.host.removals
        #expect(received.isEmpty && removals.isEmpty)
        #expect(await setup.coordinator.issues().isEmpty)
        #expect(try await setup.coordinator.boardIDs() == [setup.boardID])
    }

    // MARK: Depois de enviar

    @Test("O que o iCloud aceitou fica gravado em disco: a base, as marcas de alteração, os arquivos e os números de empilhamento")
    func confirmationsArePersisted() async throws {
        let note = makeNote()
        let image = BoardItem(
            kind: .image, title: "Foto", createdAt: SyncFixtures.otherFractionalDate, position: BoardPoint(x: 50, y: 50),
            fileName: Self.imageFile)
        let board = Board(items: [note, image])
        let setup = try await syncedSetup(board: board, files: [Self.imageFile])
        defer { cleanUp(setup) }

        // Outra instância da loja, como depois de reabrir o app.
        let reopened = SyncMetadataStore(directory: setup.syncDirectory)
        let state = try #require(try await reopened.state(for: setup.boardID))

        #expect(Set(state.base.items) == Set(board.items.map(SharedFieldPolicy.shared)))
        #expect(state.baseName == "Casa" && state.baseBoardFormatVersion == board.requiredFormatVersion)
        #expect(state.systemFields["mural"] == Data("v1:mural".utf8))
        #expect(state.systemFields[note.id.uuidString] == Data("v1:\(note.id.uuidString)".utf8))
        #expect(state.uploadedFiles == [Self.imageFile] && state.mediaOwners[Self.imageFile] == image.id)
        #expect(Set(state.layers.keys) == Set(board.items.map(\.id)))
    }

    @Test("Apagar aqui: o iCloud confirma o apagamento e a base esquece o cartão, o arquivo e o dono dele")
    func confirmedDeletionsLeaveTheBase() async throws {
        let note = makeNote()
        let image = BoardItem(
            kind: .image, title: "Foto", createdAt: SyncFixtures.otherFractionalDate, position: BoardPoint(x: 50, y: 50),
            fileName: Self.imageFile)
        let setup = try await syncedSetup(board: Board(items: [note, image]), files: [Self.imageFile])
        defer { cleanUp(setup) }

        await edit(setup) { $0.items.removeAll { $0.id == image.id } }
        let pending = try await setup.coordinator.pendingChanges(for: setup.boardID)
        #expect(pending == setup.deletes([image.id.uuidString, Self.imageFile]))

        #expect(try await accept(pending, in: setup, tag: "v2").isEmpty)
        let state = try await storedState(setup)
        #expect(state.base.items.map(\.id) == [note.id] && state.layers.keys.contains(image.id) == false)
        #expect(state.uploadedFiles.isEmpty && state.mediaOwners.isEmpty)
        #expect(state.systemFields[image.id.uuidString] == nil && state.systemFields[Self.imageFile] == nil)
    }

    @Test("Envio confirmado só em parte: o que o iCloud aceitou entra na base e o resto segue pendente, com o aviso da recusa")
    func partialConfirmationKeepsTheRestPending() async throws {
        let first = makeNote("A", x: 10)
        let second = makeNote("B", x: 20)
        let third = makeNote("C", x: 30)
        let setup = try await makeSetup(board: Board(items: [first, second, third]))
        defer { cleanUp(setup) }
        let pending = try await setup.coordinator.startTracking(setup.boardID, cloud: setup.cloud)
        let ids = [first, second, third].map(\.id.uuidString)
        #expect(pending == setup.saves(ids + ["mural"]))

        // O iCloud aceita A e B, recusa o registro do mural e nem chega a tratar C.
        let accepted = [try await sentRecord(setup.recordID(first), in: setup), try await sentRecord(setup.recordID(second), in: setup)]
        let failure = SyncSaveFailure.other(setup.recordID("mural"), "falha passageira")
        let rest = try await setup.coordinator.handleSent(saved: accepted, deleted: [], failures: [failure])

        #expect(rest == setup.saves([third.id.uuidString, "mural"]))
        #expect(await setup.coordinator.issues()[setup.boardID] == .other("falha passageira"))
        let partial = try await storedState(setup)
        #expect(Set(partial.base.items.map(\.id)) == [first.id, second.id] && partial.baseName == nil)

        #expect(try await accept(rest, in: setup, tag: "v2").isEmpty)
        #expect(await setup.coordinator.issues().isEmpty, "um envio aceito sem recusa limpa o aviso")
        let done = try await storedState(setup)
        #expect(done.systemFields[first.id.uuidString] == Data("v1:\(first.id.uuidString)".utf8), "A mantém a marca do primeiro envio")
        #expect(done.systemFields[third.id.uuidString] == Data("v2:\(third.id.uuidString)".utf8))
        #expect(done.baseName == "Casa")
    }

    @Test("Conflito de gravação: a versão do servidor é juntada ao cartão daqui, e o que difere dela continua pendente")
    func conflictMergesTheServerVersion() async throws {
        let note = makeNote()
        let setup = try await syncedSetup(board: Board(items: [note]))
        defer { cleanUp(setup) }
        let layer = try #require(try await storedState(setup).layers[note.id])

        // Aqui mudou o título; outra pessoa mudou a etiqueta, e o servidor recusou a gravação daqui.
        await edit(setup) { $0.items[0].title = "Título daqui" }
        var server = note
        server.tag = "ETIQUETA"
        let serverRecord = try serverCard(server, layer: layer, mark: "servidor-2", in: setup)
        let pending = try await setup.coordinator.handleSent(
            saved: [], deleted: [], failures: [.conflict(serverRecord: serverRecord)])

        let merged = try #require(await setup.host.board(setup.boardID).items.first)
        #expect(merged.title == "Título daqui" && merged.tag == "ETIQUETA")
        #expect(pending == setup.saves([note.id.uuidString]), "o juntado difere do servidor: falta enviar")
        let received = try #require(await setup.host.received.first)
        #expect(received.changes.savedItems == [SharedFieldPolicy.shared(server)] && received.previousBase.items == [note])
        let next = try #require(try await setup.coordinator.record(for: setup.recordID(note)))
        #expect(next.systemFields == Data("servidor-2".utf8), "o próximo envio leva a marca do servidor")
    }

    @Test("Registro apagado no iCloud durante a regravação: o cartão editado aqui vira cópia de conflito, a ser enviada")
    func unknownItemTurnsIntoADeletion() async throws {
        let note = makeNote(text: "Original")
        let setup = try await syncedSetup(board: Board(items: [note]))
        defer { cleanUp(setup) }

        await edit(setup) { $0.items[0].text = "Editado aqui" }
        let pending = try await setup.coordinator.handleSent(
            saved: [], deleted: [], failures: [.unknownItem(setup.recordID(note))])

        let board = await setup.host.board(setup.boardID)
        let copy = try #require(board.items.first)
        #expect(board.items.count == 1 && copy.id != note.id && copy.text == "Editado aqui")
        #expect(copy.title.hasSuffix("(cópia de conflito)"))
        #expect(pending == setup.saves([copy.id.uuidString]), "o original já não existe no iCloud: só a cópia é enviada")
        let received = try #require(await setup.host.received.first)
        #expect(received.changes.deletedItemIDs == [note.id])
    }

    @Test("Zona inexistente numa gravação: o mural é removido, como numa zona apagada")
    func missingZoneOnSaveRemovesTheBoard() async throws {
        let setup = try await syncedSetup(board: Board(items: [makeNote()]))
        defer { cleanUp(setup) }

        let pending = try await setup.coordinator.handleSent(saved: [], deleted: [], failures: [.zoneMissing(setup.zone)])

        #expect(pending.isEmpty)
        #expect(await setup.host.removals == [SyncTestHost.Removal(board: setup.boardID, reason: .zoneDeleted)])
        #expect(try await setup.store.state(for: setup.boardID) == nil)
        #expect(try await setup.coordinator.boardIDs().isEmpty)
    }

    @Test("Cota vira aviso do mural e segue pendente, nada se perde, e um envio aceito depois limpa o aviso")
    func quotaBecomesAnIssueAndClearsOnSuccess() async throws {
        let note = makeNote()
        let setup = try await syncedSetup(board: Board(items: [note]))
        defer { cleanUp(setup) }
        await edit(setup) { $0.items[0].title = "Mudou" }
        let id = setup.recordID(note)

        let quota = try await setup.coordinator.handleSent(saved: [], deleted: [], failures: [.quotaExceeded(id)])
        let quotaIssue = await setup.coordinator.issues()[setup.boardID]
        #expect(quota == [.save(id)] && quotaIssue == .quotaExceeded)

        #expect(try await accept(quota, in: setup, tag: "v2").isEmpty)
        #expect(await setup.coordinator.issues().isEmpty)
    }

    @Test("Recusa por permissão vira aviso e para o envio, sem perder a mudança, até a permissão nova chegar por startTracking")
    func permissionRefusalStopsSendingUntilThePermissionIsKnown() async throws {
        let note = makeNote()
        let setup = try await syncedSetup(board: Board(items: [note]))
        defer { cleanUp(setup) }
        await edit(setup) { $0.items[0].title = "Mudou" }
        let id = setup.recordID(note)

        let refused = try await setup.coordinator.handleSent(saved: [], deleted: [], failures: [.permission(id)])
        #expect(refused.isEmpty, "reenviar daria a mesma recusa")
        #expect(await setup.coordinator.issues()[setup.boardID] == .readOnly)
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
        #expect(try await setup.coordinator.record(for: id) == nil)

        // O app confere a permissão: só ver. Nada é enviado, e a mudança daqui continua no mural.
        var readOnly = setup.cloud
        readOnly.permission = .readOnly
        #expect(try await setup.coordinator.startTracking(setup.boardID, cloud: readOnly).isEmpty)
        #expect(await setup.coordinator.issues()[setup.boardID] == nil)
        #expect(await setup.host.board(setup.boardID).items.first?.title == "Mudou")

        // O dono devolve a edição: a mudança volta a ser pendente e sobe.
        let pending = try await setup.coordinator.startTracking(setup.boardID, cloud: setup.cloud)
        #expect(pending == [.save(id)])
        #expect(try await accept(pending, in: setup, tag: "v2").isEmpty)
    }

    // MARK: Zona apagada

    @Test(
        "Zona apagada, acesso perdido, conta trocada ou dados apagados do iCloud: o estado some, o host é avisado do motivo e os avisos do mural também",
        arguments: [
            BoardRemovalReason.zoneDeleted, .accessRevoked, .accountChanged, .cloudDataErased,
        ])
    func removedBoardIsForgotten(reason: BoardRemovalReason) async throws {
        let note = makeNote()
        let setup = try await syncedSetup(board: Board(items: [note]))
        defer { cleanUp(setup) }
        await edit(setup) { $0.items[0].title = "Mudou" }
        _ = try await setup.coordinator.handleSent(saved: [], deleted: [], failures: [.quotaExceeded(setup.recordID(note))])
        #expect(await setup.coordinator.issues().count == 1)

        try await setup.coordinator.handleZoneDeleted(setup.zone, reason: reason)

        #expect(await setup.host.removals == [SyncTestHost.Removal(board: setup.boardID, reason: reason)])
        #expect(try await setup.store.state(for: setup.boardID) == nil)
        #expect(try await setup.coordinator.boardIDs().isEmpty)
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
        #expect(await setup.coordinator.issues().isEmpty)
    }

    // MARK: O que chegou

    @Test("Gravação que falha ao juntar: o estado antigo fica, nada vira apagamento, o aviso aparece e a busca completa recupera tudo")
    func failedLocalSaveIsRecoveredByAFullFetch() async throws {
        let kept = makeNote("Fica", x: 10)
        let removed = makeNote("Sai", x: 20)
        let setup = try await syncedSetup(board: Board(items: [kept, removed]))
        defer { cleanUp(setup) }
        let before = try await storedState(setup)
        let top = (before.layers.values.max() ?? 0) + 1

        // Chega um cartão novo e o app não consegue gravar.
        let arrived = makeNote("Chegou", x: 30)
        await setup.host.failNextApply()
        let pending = try await setup.coordinator.handleFetched(
            saved: [try serverCard(arrived, layer: top, mark: "s-1", in: setup)], deleted: [])

        #expect(pending.isEmpty, "o mural daqui e o estado antigo combinam: nada a enviar, nem o apagamento do que chegou")
        let failed = try await storedState(setup)
        #expect(failed.base == before.base && failed.layers == before.layers && failed.needsFullFetch)
        #expect(await setup.coordinator.issues()[setup.boardID] == .localSaveFailed)
        #expect(try await setup.coordinator.zonesNeedingFullFetch() == [setup.zone])
        #expect(await setup.host.board(setup.boardID).items.map(\.id) == [kept.id, removed.id])

        // Enquanto isso, outra pessoa apagou um cartão. A busca completa traz tudo o que a zona tem agora; o que não veio saiu.
        let zoneNow = [
            try serverCard(kept, layer: try #require(before.layers[kept.id]), mark: "v1", in: setup),
            try serverCard(arrived, layer: top, mark: "s-1", in: setup),
            serverBoard(name: "Casa", formatVersion: try #require(before.baseBoardFormatVersion), mark: "m-1", in: setup),
        ]
        let afterFull = try await setup.coordinator.handleFullFetch(setup.zone, records: zoneNow)

        #expect(afterFull.isEmpty)
        let recovered = await setup.host.board(setup.boardID)
        #expect(Set(recovered.items.map(\.id)) == [kept.id, arrived.id])
        let done = try await storedState(setup)
        #expect(!done.needsFullFetch && Set(done.base.items.map(\.id)) == [kept.id, arrived.id] && done.baseName == "Casa")
        #expect(await setup.coordinator.issues()[setup.boardID] == nil)
        #expect(try await setup.coordinator.zonesNeedingFullFetch().isEmpty)
    }

    @Test("A marca de busca completa vai ao disco só quando ligada, e o estado gravado sem ela abre desligado")
    func fullFetchMarkIsStoredOnlyWhenSet() throws {
        let cloud = BoardCloudInfo(
            database: .private, zoneName: CloudSchema.zoneName(for: BoardID()), zoneOwnerName: CloudZoneID.defaultOwnerName,
            permission: .owner)
        let plain = try JSONEncoder().encode(BoardSyncState(cloud: cloud))
        #expect(!String(decoding: plain, as: UTF8.self).contains("needsFullFetch"))
        #expect(try JSONDecoder().decode(BoardSyncState.self, from: plain).needsFullFetch == false)

        let marked = try JSONEncoder().encode(BoardSyncState(cloud: cloud, needsFullFetch: true))
        #expect(try JSONDecoder().decode(BoardSyncState.self, from: marked).needsFullFetch)
    }

    @Test("Mural de app mais novo: o que chega é entregue ao host, nada é enviado nem montado, e o aviso some quando a versão couber")
    func boardFromANewerAppBlocksSending() async throws {
        let note = makeNote()
        let setup = try await syncedSetup(board: Board(items: [note]))
        defer { cleanUp(setup) }
        await edit(setup) { $0.items[0].title = "Mudou aqui" }
        let newer = Board.currentFormatVersion + 1

        let blocked = try await setup.coordinator.handleFetched(
            saved: [serverBoard(name: "Nome novo", formatVersion: newer, mark: "m2", in: setup)], deleted: [])

        #expect(blocked.isEmpty)
        #expect(await setup.coordinator.issues()[setup.boardID] == .needsNewerApp)
        #expect(await setup.host.name(setup.boardID) == "Nome novo", "o que chega continua sendo entregue")
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
        #expect(try await setup.coordinator.record(for: setup.recordID(note)) == nil)
        #expect(try await storedState(setup).baseBoardFormatVersion == newer)

        // O app foi atualizado: o mural passa a caber e a edição guardada volta a ser pendente.
        let fits = try await setup.coordinator.handleFetched(
            saved: [serverBoard(name: "Nome novo", formatVersion: Board.currentFormatVersion, mark: "m3", in: setup)], deleted: [])
        #expect(await setup.coordinator.issues().isEmpty)
        #expect(fits == setup.saves([note.id.uuidString, "mural"]))
    }

    @Test("Registro ilegível é ignorado e anotado: não derruba os outros, não chama o host sozinho e o aviso some quando ele chega legível")
    func unreadableRecordsAreReportedAndSkipped() async throws {
        let existing = makeNote()
        let setup = try await syncedSetup(board: Board(items: [existing]))
        defer { cleanUp(setup) }
        let broken = makeNote("Quebrado")
        let brokenRecord = CloudRecord(
            id: setup.recordID(broken), type: "Card", fields: ["title": .string("sem tipo")], systemFields: Data("s".utf8))

        let alone = try await setup.coordinator.handleFetched(saved: [brokenRecord], deleted: [])
        let applied = await setup.host.received
        #expect(alone.isEmpty && applied.isEmpty, "só o registro ilegível: não há o que aplicar")
        guard case .other(let message)? = await setup.coordinator.issues()[setup.boardID] else {
            Issue.record("o registro ilegível não virou aviso")
            return
        }
        #expect(message.contains(broken.id.uuidString))

        let valid = makeNote("Válido", x: 80)
        let mixed = try await setup.coordinator.handleFetched(
            saved: [brokenRecord, try serverCard(valid, layer: 9, mark: "s1", in: setup)], deleted: [])
        #expect(mixed.isEmpty)
        #expect(await setup.host.board(setup.boardID).items.map(\.id) == [existing.id, valid.id])
        #expect(await setup.coordinator.issues()[setup.boardID] != nil, "o ilegível continua anotado")

        _ = try await setup.coordinator.handleFetched(saved: [try serverCard(broken, layer: 10, mark: "s2", in: setup)], deleted: [])
        #expect(await setup.coordinator.issues().isEmpty)
    }

    @Test("Enquanto o host junta, as pendências e os registros seguem no estado anterior: o cartão que chega não vira .delete")
    func pendingChangesDuringTheMergeUseThePreviousState() async throws {
        let existing = makeNote()
        let setup = try await syncedSetup(board: Board(items: [existing]))
        defer { cleanUp(setup) }
        let arriving = BoardItem(
            kind: .sticky, title: "Chegando", createdAt: SyncFixtures.otherFractionalDate, position: BoardPoint(x: 300, y: 40),
            text: "Chegando")
        let record = try serverCard(arriving, layer: 5, mark: "s1", in: setup)
        let gate = SyncTestGate()
        await setup.host.hold(gate)

        let fetching = Task { try await setup.coordinator.handleFetched(saved: [record], deleted: []) }
        await gate.waitUntilHolding()

        // O host ainda não juntou: o mural daqui não tem o cartão. Com a base já nova, ele pareceria apagado.
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
        #expect(try await setup.coordinator.record(for: setup.recordID(arriving)) == nil)
        #expect(try await storedState(setup).base.item(id: arriving.id) == nil, "o estado novo só vale depois do host")

        await gate.release()
        let pending = try await fetching.value

        #expect(pending.isEmpty, "o que chegou e já foi juntado não volta ao iCloud")
        #expect(await setup.host.board(setup.boardID).items.map(\.id) == [existing.id, arriving.id])
        #expect(try await storedState(setup).base.item(id: arriving.id) != nil)
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
    }

    @Test("Dois eventos ao mesmo tempo não se atropelam: o segundo espera o primeiro e nenhuma chegada se perde")
    func overlappingEventsRunOneAtATime() async throws {
        let setup = try await syncedSetup(board: Board(items: [makeNote()]))
        defer { cleanUp(setup) }
        let first = makeNote("Primeiro", x: 100)
        let second = makeNote("Segundo", x: 200)
        let firstRecord = try serverCard(first, layer: 5, mark: "s1", in: setup)
        let secondRecord = try serverCard(second, layer: 6, mark: "s2", in: setup)
        let gate = SyncTestGate()
        await setup.host.hold(gate)

        let fetchingFirst = Task { try await setup.coordinator.handleFetched(saved: [firstRecord], deleted: []) }
        await gate.waitUntilHolding()
        let fetchingSecond = Task { try await setup.coordinator.handleFetched(saved: [secondRecord], deleted: []) }
        // Tempo para o segundo evento chegar ao coordenador: sem a fila ele leria o estado antigo e gravaria por cima do primeiro.
        try await Task.sleep(for: .milliseconds(100))
        await gate.release()
        _ = try await fetchingFirst.value
        _ = try await fetchingSecond.value

        let state = try await storedState(setup)
        let localIDs = await setup.host.board(setup.boardID).items.map(\.id)
        let applied = await setup.host.received
        #expect(Set(state.base.items.map(\.id)).isSuperset(of: [first.id, second.id]))
        #expect(Set(localIDs).isSuperset(of: [first.id, second.id]))
        #expect(applied.count == 2)
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
    }

    // MARK: Cartão grande demais

    @Test("Cartão que estoura o limite do registro sai das pendências até o conteúdo mudar, e vira aviso do mural")
    func oversizedCardIsHeldBackUntilItChanges() async throws {
        let small = makeNote("Pequeno")
        let setup = try await syncedSetup(board: Board(items: [small]))
        defer { cleanUp(setup) }
        let huge = makeNote("Gigante", text: String(repeating: "x", count: CardRecordMapping.maximumFieldBytes + 100), x: 90)
        await edit(setup) { $0.items.append(huge) }
        let hugeID = setup.recordID(huge)
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID) == setup.saves([huge.id.uuidString]))

        await #expect(throws: CardRecordMappingError.recordTooLarge(huge.id)) {
            _ = try await setup.coordinator.record(for: hugeID)
        }

        #expect(await setup.coordinator.issues()[setup.boardID] == .recordTooLarge(huge.id))
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty, "o conteúdo é o mesmo que estourou")

        // O conteúdo muda e ainda estoura: é tentado de novo e continua de fora.
        await edit(setup) { $0.items[1].text = String(repeating: "y", count: CardRecordMapping.maximumFieldBytes + 100) }
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID) == setup.saves([huge.id.uuidString]))
        await #expect(throws: CardRecordMappingError.recordTooLarge(huge.id)) {
            _ = try await setup.coordinator.record(for: hugeID)
        }
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)

        // O conteúdo encolhe: volta a ser pendente, o registro é montado e o aviso some.
        await edit(setup) { $0.items[1].text = "curto" }
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID) == setup.saves([huge.id.uuidString]))
        #expect(try await setup.coordinator.record(for: hugeID) != nil)
        #expect(await setup.coordinator.issues().isEmpty)
    }

    // MARK: Zona nova

    /// Um Mac sem o mural, cujo coordenador acabou de adotar a zona.
    private func adoptedSetup(name: String? = nil) async throws -> Setup {
        let setup = try await makeSetup(hasLocalBoard: false)
        let result = try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: name)
        try #require(result == .adopted, "a adoção devolveu \(result)")
        return setup
    }

    @Test("Adotar a zona nova: o host cria o mural vazio, o estado nasce esperando a primeira busca e o aviso é só informativo")
    func adoptingCreatesTheBoardAwaitingTheFirstFetch() async throws {
        let setup = try await makeSetup(hasLocalBoard: false)
        defer { cleanUp(setup) }
        #expect(try await setup.coordinator.isTracking(setup.boardID) == false)

        let result = try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil)

        #expect(result == .adopted)
        #expect(await setup.host.adoptions == [SyncTestHost.Adoption(board: setup.boardID, cloud: setup.cloud, name: nil)])
        #expect(await setup.host.name(setup.boardID) == SyncTestHost.adoptedDefaultName)
        #expect(await setup.host.board(setup.boardID) == Board())
        let state = try await storedState(setup)
        #expect(state.isAwaitingFirstFetch && !state.needsFullFetch && state.cloud == setup.cloud)
        #expect(try await setup.coordinator.isTracking(setup.boardID))
        #expect(try await setup.coordinator.boardIDs() == [setup.boardID])
        #expect(try await setup.coordinator.zonesNeedingFullFetch() == [setup.zone])
        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
        #expect(await setup.coordinator.issues() == [setup.boardID: .awaitingFirstFetch])
    }

    @Test("O nome provisório que o coordenador passa é o do pacote criado pelo host")
    func adoptedNameReachesTheHost() async throws {
        let setup = try await adoptedSetup(name: "Mural da Ana")
        defer { cleanUp(setup) }

        #expect(await setup.host.name(setup.boardID) == "Mural da Ana")
        #expect(await setup.host.adoptions.first?.name == "Mural da Ana")
    }

    @Test("Esperando a primeira busca nada sobe: nem o nome provisório, nem o que se escreveu no pacote provisório, nem após startTracking")
    func awaitingBoardNeverSends() async throws {
        let setup = try await adoptedSetup(name: "Provisório")
        defer { cleanUp(setup) }
        let note = makeNote()
        await edit(setup) { $0.items.append(note) }
        await setup.host.rename("Outro provisório", for: setup.boardID)

        #expect(try await setup.coordinator.pendingChanges(for: setup.boardID).isEmpty)
        #expect(try await setup.coordinator.record(for: setup.recordID(CloudSchema.muralRecordName)) == nil)
        #expect(try await setup.coordinator.record(for: setup.recordID(note)) == nil)

        // A permissão nova chega por startTracking, que não encerra a espera.
        var granted = setup.cloud
        granted.permission = .readWrite
        #expect(try await setup.coordinator.startTracking(setup.boardID, cloud: granted).isEmpty)
        let state = try await storedState(setup)
        #expect(state.isAwaitingFirstFetch && state.cloud.permission == .readWrite)
        #expect(await setup.coordinator.issues()[setup.boardID] == .awaitingFirstFetch)
    }

    @Test("A busca completa traz o conteúdo e o nome, desliga a espera e não deixa nada a enviar: o nome provisório nunca sobe")
    func fullFetchBringsTheContentAndEndsTheWait() async throws {
        let setup = try await adoptedSetup(name: "Provisório")
        defer { cleanUp(setup) }
        let note = makeNote("Do iCloud")
        let cloudBoard = Board(items: [note])
        let records = [
            try serverCard(note, layer: 1, mark: "s-1", in: setup),
            serverBoard(name: "Casa da Ana", formatVersion: cloudBoard.requiredFormatVersion, mark: "m-1", in: setup),
        ]

        let pending = try await setup.coordinator.handleFullFetch(setup.zone, records: records)

        #expect(pending.isEmpty, "o conteúdo e o nome daqui são os do iCloud")
        #expect(await setup.host.name(setup.boardID) == "Casa da Ana")
        #expect(await setup.host.board(setup.boardID).items.map(\.id) == [note.id])
        let state = try await storedState(setup)
        #expect(!state.isAwaitingFirstFetch && !state.needsFullFetch && state.baseName == "Casa da Ana")
        #expect(await setup.coordinator.issues().isEmpty)
        #expect(try await setup.coordinator.zonesNeedingFullFetch().isEmpty)
        #expect(try await setup.coordinator.record(for: setup.recordID(CloudSchema.muralRecordName)) != nil, "agora o mural pode subir")
    }

    @Test("Só a busca completa encerra a espera, e a gravação que falha antes dela vale mais como aviso que a espera")
    func onlyAFullFetchEndsTheWait() async throws {
        let setup = try await adoptedSetup()
        defer { cleanUp(setup) }
        let arrived = makeNote("Chegou")
        let other = makeNote("Outro", x: 50)
        let card = try serverCard(arrived, layer: 1, mark: "s-1", in: setup)
        let second = try serverCard(other, layer: 2, mark: "s-2", in: setup)

        // Uma busca comum traz o cartão e o host grava, mas a espera continua.
        _ = try await setup.coordinator.handleFetched(saved: [card], deleted: [])
        #expect(await setup.host.board(setup.boardID).items.map(\.id) == [arrived.id])
        #expect(try await storedState(setup).isAwaitingFirstFetch)
        #expect(await setup.coordinator.issues()[setup.boardID] == .awaitingFirstFetch)

        // Se o host não consegue gravar, o aviso de gravação vale mais que a espera.
        await setup.host.failNextApply()
        _ = try await setup.coordinator.handleFetched(saved: [second], deleted: [])
        let failed = try await storedState(setup)
        #expect(failed.isAwaitingFirstFetch && failed.needsFullFetch)
        #expect(await setup.coordinator.issues()[setup.boardID] == .localSaveFailed)

        // A busca completa que dá certo apaga as duas marcas.
        let cloudBoard = Board(items: [arrived, other])
        let records = [
            card, second, serverBoard(name: "Casa", formatVersion: cloudBoard.requiredFormatVersion, mark: "m-1", in: setup),
        ]
        _ = try await setup.coordinator.handleFullFetch(setup.zone, records: records)
        let done = try await storedState(setup)
        #expect(!done.isAwaitingFirstFetch && !done.needsFullFetch)
        #expect(await setup.coordinator.issues().isEmpty)
    }

    @Test("Quem espera a primeira busca vem do estado guardado: a gravação que falhou não o esconde, e só a busca completa o tira")
    func boardsAwaitingFirstFetchFollowsTheStoredMark() async throws {
        let setup = try await adoptedSetup()
        defer { cleanUp(setup) }
        let arrived = makeNote("Chegou")
        let card = try serverCard(arrived, layer: 1, mark: "s-1", in: setup)
        #expect(try await setup.coordinator.boardsAwaitingFirstFetch() == [setup.boardID])

        // O host não consegue gravar: `issues()` mostra a gravação que falhou, mas o pacote continua provisório.
        await setup.host.failNextApply()
        _ = try await setup.coordinator.handleFetched(saved: [card], deleted: [])
        #expect(await setup.coordinator.issues()[setup.boardID] == .localSaveFailed)
        #expect(try await setup.coordinator.boardsAwaitingFirstFetch() == [setup.boardID])

        // Um coordenador novo, que ainda não leu nada, lê do disco, e cada banco vê só os murais dele.
        let store = SyncMetadataStore(directory: setup.syncDirectory)
        let restarted = BoardSyncCoordinator(scope: .private, store: store, host: setup.host)
        #expect(try await restarted.boardsAwaitingFirstFetch() == [setup.boardID])
        let sharedID = BoardID()
        let sharedInfo = BoardCloudInfo(
            database: .shared, zoneName: CloudSchema.zoneName(for: sharedID), zoneOwnerName: "_dono", permission: .readOnly)
        try await store.save(BoardSyncState(cloud: sharedInfo, isAwaitingFirstFetch: true, isAdopted: true), for: sharedID)
        #expect(try await restarted.boardsAwaitingFirstFetch() == [setup.boardID], "o mural do banco compartilhado não é deste banco")
        let shared = BoardSyncCoordinator(scope: .shared, store: store, host: setup.host)
        #expect(try await shared.boardsAwaitingFirstFetch() == [sharedID])

        let cloudBoard = Board(items: [arrived])
        let records = [
            card, serverBoard(name: "Casa", formatVersion: cloudBoard.requiredFormatVersion, mark: "m-1", in: setup),
        ]
        _ = try await setup.coordinator.handleFullFetch(setup.zone, records: records)
        #expect(try await setup.coordinator.boardsAwaitingFirstFetch().isEmpty)
        #expect(try await restarted.boardsAwaitingFirstFetch().isEmpty)
    }

    @Test("Parar de acompanhar tira o mural de quem espera a primeira busca")
    func stoppingTrackingEndsTheAwaitingQuery() async throws {
        let setup = try await adoptedSetup()
        defer { cleanUp(setup) }
        #expect(try await setup.coordinator.boardsAwaitingFirstFetch() == [setup.boardID])

        try await setup.coordinator.stopTracking(setup.boardID)

        #expect(try await setup.coordinator.boardsAwaitingFirstFetch().isEmpty)
    }

    @Test("A pergunta feita enquanto o host junta a busca completa espera o evento e já vê a espera desligada")
    func awaitingQueryWaitsForTheRunningEvent() async throws {
        let setup = try await adoptedSetup()
        defer { cleanUp(setup) }
        let note = makeNote("Do iCloud")
        let cloudBoard = Board(items: [note])
        let records = [
            try serverCard(note, layer: 1, mark: "s-1", in: setup),
            serverBoard(name: "Casa", formatVersion: cloudBoard.requiredFormatVersion, mark: "m-1", in: setup),
        ]
        let gate = SyncTestGate()
        await setup.host.hold(gate)

        let fetching = Task { try await setup.coordinator.handleFullFetch(setup.zone, records: records) }
        await gate.waitUntilHolding()
        let asking = Task { try await setup.coordinator.boardsAwaitingFirstFetch() }
        // Tempo para a pergunta chegar ao coordenador: sem a espera ela leria a marca ainda ligada, como o app a leria ao reagir ao
        // aviso do host, que vem antes de o estado novo ser gravado.
        try await Task.sleep(for: .milliseconds(100))
        await gate.release()
        _ = try await fetching.value

        #expect(try await asking.value.isEmpty)
    }

    @Test("Adotar de novo, durante a espera ou depois dela, não cria nada: a zona já é acompanhada")
    func adoptingTwiceIsAlreadyTracked() async throws {
        let setup = try await adoptedSetup()
        defer { cleanUp(setup) }

        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: "Outro") == .alreadyTracked)

        _ = try await setup.coordinator.handleFullFetch(setup.zone, records: [])
        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: "Outro") == .alreadyTracked)
        #expect(await setup.host.adoptions.count == 1, "o host só foi chamado na primeira vez")
        #expect(await setup.host.name(setup.boardID) == SyncTestHost.adoptedDefaultName)
    }

    @Test("Zona recusada neste banco não é adotada, qualquer que seja o dono nela, e o host nem é chamado")
    func declinedZoneIsNotAdopted() async throws {
        let setup = try await makeSetup(hasLocalBoard: false)
        defer { cleanUp(setup) }
        try await setup.store.saveDeclinedZones([CloudZoneID(name: setup.zone.name, ownerName: "_outro")], for: .private)

        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil) == .declined)

        #expect(await setup.host.adoptions.isEmpty)
        #expect(try await setup.store.state(for: setup.boardID) == nil)
        #expect(try await setup.coordinator.zonesNeedingFullFetch().isEmpty)

        // A recusa é do banco: no outro banco a mesma zona não está recusada.
        let sharedInfo = BoardCloudInfo(
            database: .shared, zoneName: setup.zone.name, zoneOwnerName: "_dono", ownerDisplayName: "Ana", permission: .readOnly)
        let shared = BoardSyncCoordinator(scope: .shared, store: setup.store, host: setup.host)
        let sharedZone = CloudZoneID(name: setup.zone.name, ownerName: "_dono")
        #expect(try await shared.adoptZone(sharedZone, cloud: sharedInfo, name: nil) == .adopted)
    }

    @Test("Recusar o mural guarda a zona do estado; depois de parar de acompanhar, a zona não é adotada de novo")
    func decliningKeepsTheZoneOfTheState() async throws {
        let setup = try await syncedSetup(board: Board(items: [makeNote()]))
        defer { cleanUp(setup) }
        #expect(try await setup.coordinator.declinedZones().isEmpty)

        try await setup.coordinator.declineZone(of: setup.boardID)
        try await setup.coordinator.declineZone(of: BoardID())
        try await setup.coordinator.stopTracking(setup.boardID)

        #expect(try await setup.coordinator.declinedZones() == [setup.zone], "o mural desconhecido não guarda nada")
        #expect(try await setup.store.declinedZones(for: .private) == [setup.zone])
        #expect(try await setup.store.declinedZones(for: .shared).isEmpty)
        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil) == .declined)
        #expect(try await setup.coordinator.isTracking(setup.boardID) == false)
    }

    @Test("O servidor confirma o apagamento: a zona sai das recusadas, mesmo sem estado guardado, e só ela")
    func zoneDeletionEndsTheDecline() async throws {
        let setup = try await makeSetup(hasLocalBoard: false)
        defer { cleanUp(setup) }
        let other = CloudZoneID(name: CloudSchema.zoneName(for: BoardID()))
        try await setup.store.saveDeclinedZones([setup.zone, other], for: .private)
        try await setup.store.saveDeclinedZones([setup.zone], for: .shared)

        try await setup.coordinator.handleZoneDeleted(setup.zone, reason: .zoneDeleted)

        #expect(try await setup.coordinator.declinedZones() == [other])
        #expect(try await setup.store.declinedZones(for: .shared) == [setup.zone], "o outro banco não é tocado")
        #expect(await setup.host.removals.isEmpty, "não havia mural acompanhado: nada a avisar ao host")

        // Uma zona que não é de mural não mexe na lista.
        try await setup.coordinator.handleZoneDeleted(CloudZoneID(name: "Outra"), reason: .zoneDeleted)
        #expect(try await setup.coordinator.declinedZones() == [other])
    }

    @Test("Apagar a zona de um mural acompanhado e recusado remove o mural e a recusa")
    func zoneDeletionRemovesTheBoardAndTheDecline() async throws {
        let setup = try await syncedSetup(board: Board(items: [makeNote()]))
        defer { cleanUp(setup) }
        try await setup.coordinator.declineZone(of: setup.boardID)

        try await setup.coordinator.handleZoneDeleted(setup.zone, reason: .accessRevoked)

        #expect(await setup.host.removals == [SyncTestHost.Removal(board: setup.boardID, reason: .accessRevoked)])
        #expect(try await setup.coordinator.boardIDs().isEmpty)
        #expect(try await setup.coordinator.declinedZones().isEmpty)
    }

    @Test("Voltar a aceitar a zona recusada tira só ela das recusadas, neste banco, e a zona volta a ser adotada")
    func undecliningLetsTheZoneBeAdoptedAgain() async throws {
        let setup = try await makeSetup(hasLocalBoard: false)
        defer { cleanUp(setup) }
        let other = CloudZoneID(name: CloudSchema.zoneName(for: BoardID()))
        try await setup.store.saveDeclinedZones([CloudZoneID(name: setup.zone.name, ownerName: "_outro"), other], for: .private)
        try await setup.store.saveDeclinedZones([setup.zone], for: .shared)
        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil) == .declined)

        try await setup.coordinator.undeclineZone(setup.zone)

        #expect(try await setup.coordinator.declinedZones() == [other], "a zona saiu pelo nome, e a outra continua recusada")
        #expect(try await setup.store.declinedZones(for: .shared) == [setup.zone], "o outro banco não é tocado")
        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil) == .adopted)

        // Zona que não estava recusada: nada muda.
        try await setup.coordinator.undeclineZone(setup.zone)
        try await setup.coordinator.undeclineZone(CloudZoneID(name: "Outra"))
        #expect(try await setup.coordinator.declinedZones() == [other])
    }

    @Test("O mesmo id acompanhado no outro banco é conflito, e o estado dele não é tocado")
    func sameIDInTheOtherDatabaseIsAConflict() async throws {
        let setup = try await makeSetup(hasLocalBoard: false)
        defer { cleanUp(setup) }
        let sharedInfo = BoardCloudInfo(
            database: .shared, zoneName: setup.zone.name, zoneOwnerName: "_dono", ownerDisplayName: "Ana", permission: .readWrite)
        let sharedState = BoardSyncState(cloud: sharedInfo, baseName: "Do outro banco")
        try await setup.store.save(sharedState, for: setup.boardID)

        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil) == .conflict)

        #expect(await setup.host.adoptions.isEmpty)
        #expect(try await setup.store.state(for: setup.boardID) == sharedState)
        #expect(try await setup.coordinator.isTracking(setup.boardID) == false, "o banco privado continua sem acompanhar")
    }

    @Test("Já existe um pacote com o mesmo id no host: conflito, sem estado novo")
    func existingLocalBoardIsAConflict() async throws {
        let setup = try await makeSetup(board: Board(items: [makeNote()]))
        defer { cleanUp(setup) }

        #expect(try await setup.coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil) == .conflict)

        #expect(await setup.host.adoptions.count == 1, "o host foi perguntado e recusou")
        #expect(try await setup.store.state(for: setup.boardID) == nil)
        #expect(await setup.host.board(setup.boardID).items.count == 1, "o mural daqui fica como estava")
        #expect(await setup.coordinator.issues().isEmpty)
    }

    @Test("Zona que não é de mural, ou banco errado: nada é criado")
    func notABoardZoneAndWrongDatabase() async throws {
        let setup = try await makeSetup(hasLocalBoard: false)
        defer { cleanUp(setup) }

        let stranger = CloudZoneID(name: "Outra")
        #expect(try await setup.coordinator.adoptZone(stranger, cloud: setup.cloud, name: nil) == .notABoardZone)

        var sharedInfo = setup.cloud
        sharedInfo.database = .shared
        await #expect(throws: BoardSyncCoordinatorError.wrongDatabase(setup.boardID)) {
            _ = try await setup.coordinator.adoptZone(setup.zone, cloud: sharedInfo, name: nil)
        }
        #expect(await setup.host.adoptions.isEmpty)
        #expect(try await setup.store.boardIDs().isEmpty)
    }

    @Test("Host que não adota zonas: a adoção falha com erro próprio e nada é gravado")
    func hostWithoutAdoptionIsUnsupported() async throws {
        let setup = try await makeSetup(hasLocalBoard: false)
        defer { cleanUp(setup) }
        let coordinator = BoardSyncCoordinator(scope: .private, store: setup.store, host: SyncHostWithoutAdoption())

        await #expect(throws: BoardSyncAdoptionError.unsupported) {
            _ = try await coordinator.adoptZone(setup.zone, cloud: setup.cloud, name: nil)
        }

        #expect(try await setup.store.state(for: setup.boardID) == nil)
    }

    @Test("Reabrir o app: o estado guardado volta esperando a primeira busca, com o aviso e a zona para buscar inteira")
    func awaitingStateSurvivesARestart() async throws {
        let setup = try await adoptedSetup()
        defer { cleanUp(setup) }

        let restarted = BoardSyncCoordinator(scope: .private, store: SyncMetadataStore(directory: setup.syncDirectory), host: setup.host)
        #expect(await restarted.issues().isEmpty, "nada foi lido ainda")
        #expect(try await restarted.boardIDs() == [setup.boardID])

        #expect(await restarted.issues() == [setup.boardID: .awaitingFirstFetch])
        #expect(try await restarted.zonesNeedingFullFetch() == [setup.zone])
        #expect(try await restarted.pendingChanges(for: setup.boardID).isEmpty)
    }
}
