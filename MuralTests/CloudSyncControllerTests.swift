import Foundation
import MuralKit
import MuralSync
import Testing

@testable import Mural

/// O controlador da sincronização e a ponte com as sessões de janela, com o iCloud falso. O "segundo Mac" é outro coordenador, com
/// um host em memória e outro motor falso sobre o mesmo `InMemoryCloud`.
@Suite("Sincronização no app: controlador e ponte", .serialized)
@MainActor
struct CloudSyncControllerTests {
    private static let editedText = "um editado lá"
    private static let mediaName = "AAAAAAAA-0000-4000-8000-000000000001.jpg"

    /// Uma data com fração de segundo, que o iCloud guarda sem perder nada.
    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000.5)

    private static func note(_ text: String) -> BoardItem {
        BoardItem(
            kind: .sticky, title: ContentClassifier.title(forText: text), createdAt: fixedDate, position: BoardPoint(x: 10, y: 20),
            text: text, stickyColor: .yellow)
    }

    private static func photo(_ file: String) -> BoardItem {
        BoardItem(kind: .image, title: "Foto", createdAt: fixedDate, position: BoardPoint(x: 50, y: 50), fileName: file)
    }

    /// Muda o texto de um cartão pelo `Board.update`, como o app faz ao editar.
    private static func setText(_ text: String, of id: UUID, in board: inout Board) {
        guard var item = board.item(id: id) else { return }
        item.text = text
        board.update(item)
    }

    // MARK: Receber

    @Test("Mural fechado: a mudança do outro Mac chega ao disco e nenhuma sessão fica aberta")
    func closedBoardReceivesRemoteChange() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(items: [card])
        let remote = try await env.putInCloud(id)

        try await remote.edit { Self.setText(Self.editedText, of: card.id, in: &$0) }
        await env.controller.fetch()

        #expect(try await env.diskBoard(id).item(id: card.id)?.text == Self.editedText)
        #expect(env.liveSessions(of: id).isEmpty, "a sessão avulsa fechou")
        #expect(env.delivery.detachedSession(for: id) == nil)
        #expect(await env.registry.ownerCount(for: id) == 0)
        #expect(env.controller.issues.isEmpty)
        await env.finish()
    }

    @Test("Mural aberto numa aba: a mudança aparece no modelo da aba e no disco, sem segunda sessão")
    func openBoardReceivesRemoteChange() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(items: [card])
        let remote = try await env.putInCloud(id)
        let tab = try #require(env.tabs.open(.saved(id), title: "Aberto"))
        await waitUntil("a aba carregar") { tab.session.model != nil }

        try await remote.edit { Self.setText(Self.editedText, of: card.id, in: &$0) }
        await env.controller.fetch()

        #expect(tab.session.model?.board.item(id: card.id)?.text == Self.editedText)
        #expect(try await env.diskBoard(id).item(id: card.id)?.text == Self.editedText)
        #expect(!tab.session.isDirty)
        let live = env.liveSessions(of: id)
        #expect(live.count == 1, "uma sessão só desse mural")
        #expect(live.first === tab.session)
        #expect(env.delivery.detachedSession(for: id) == nil)
        #expect(await env.registry.ownerCount(for: id) == 1)
        await env.finish()
    }

    @Test("O arquivo de mídia que chega vai para Items/ antes de o cartão ser gravado")
    func mediaFileArrivesBeforeTheCard() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed(items: [Self.note("um")])
        let remote = try await env.putInCloud(id)
        let tab = try #require(env.tabs.open(.saved(id), title: "Aberto"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let file = try await env.itemsDirectory(of: id).appendingPathComponent(Self.mediaName)
        let picture = Self.photo(Self.mediaName)
        let recorder = PersistRecorder()
        tab.session.onPersisted = { board, _ in
            if board.item(id: picture.id) != nil {
                recorder.fileExistedWhenCardWasSaved.append(FileManager.default.fileExists(atPath: file.path))
            }
        }

        try remote.writeFile(Self.mediaName, contents: "conteúdo da foto")
        try await remote.edit { $0.add(picture) }
        await env.controller.fetch()

        #expect(recorder.fileExistedWhenCardWasSaved == [true])
        #expect(tab.session.model?.board.item(id: picture.id) != nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "conteúdo da foto")
        await env.finish()
    }

    @Test("Mural fechado: o arquivo que chega vai para Items/, sem sobrescrever o que já existe nem sair da pasta")
    func filesAreCopiedWithoutOverwriting() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed(items: [])
        let items = try await env.itemsDirectory(of: id)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        try Data("antigo".utf8).write(to: items.appendingPathComponent("existente.jpg"))
        let source = env.directory.appendingPathComponent("origem", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        for name in ["novo.jpg", "novo-de-existente.jpg", "fora.jpg"] {
            try Data("novo".utf8).write(to: source.appendingPathComponent(name))
        }
        let received = ReceivedChanges(
            files: [
                "existente.jpg": source.appendingPathComponent("novo-de-existente.jpg"),
                "novo.jpg": source.appendingPathComponent("novo.jpg"),
                "../fora.jpg": source.appendingPathComponent("fora.jpg"),
            ])

        try await env.bridge().applyRemote(id, received: received)

        #expect(try String(contentsOf: items.appendingPathComponent("existente.jpg"), encoding: .utf8) == "antigo")
        #expect(try String(contentsOf: items.appendingPathComponent("novo.jpg"), encoding: .utf8) == "novo")
        #expect(!FileManager.default.fileExists(atPath: items.deletingLastPathComponent().appendingPathComponent("fora.jpg").path))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: items.path).filter { $0.hasSuffix(".partial") }
        #expect(leftovers.isEmpty)
        #expect(env.liveSessions(of: id).isEmpty)
        await env.finish()
    }

    @Test("Mural que não abre: applyRemote lança e não deixa sessão para trás")
    func applyRemoteThrowsForMissingBoard() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        _ = try await env.library.bootstrap()
        let id = BoardID()

        await #expect(throws: (any Error).self) {
            try await env.bridge().applyRemote(id, received: ReceivedChanges())
        }

        #expect(env.liveSessions(of: id).isEmpty)
        #expect(env.delivery.detachedSession(for: id) == nil)
        #expect(await env.registry.ownerCount(for: id) == 0)
    }

    @Test("Uma colagem e uma busca ao mesmo tempo no mural fechado não se atropelam")
    func pasteAndFetchShareTheQueue() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(items: [card])
        let remote = try await env.putInCloud(id)
        let entry = try #require(try await env.library.listSaved().first { $0.route == .saved(id) })
        try await remote.edit { Self.setText(Self.editedText, of: card.id, in: &$0) }

        async let delivered = env.delivery.deliver(.pasted(.text("Colado")), textKind: .sticky, to: entry)
        async let fetched: Void = env.controller.fetch()
        let outcome = await delivered
        await fetched

        #expect(outcome == .delivered(count: 1))
        let disk = try await env.diskBoard(id)
        #expect(disk.item(id: card.id)?.text == Self.editedText, "a busca não apagou a colagem nem o contrário")
        #expect(disk.items.contains { $0.text == "Colado" })
        #expect(env.liveSessions(of: id).isEmpty)
        #expect(env.delivery.detachedSession(for: id) == nil)
        #expect(await env.registry.ownerCount(for: id) == 0)
        await env.finish()
    }

    // MARK: O que sobe

    @Test("localBoard: sem janela lê o disco; com edição ainda não gravada devolve o último gravado")
    func localBoardIsAlwaysWhatIsOnDisk() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(name: "Local", items: [card])
        let bridge = env.bridge()

        let closed = try #require(await bridge.localBoard(id))
        #expect(closed.name == "Local")
        #expect(closed.board.items.map(\.id) == [card.id])
        #expect(closed.itemsDirectory.lastPathComponent == "Items")
        #expect(closed.itemsDirectory.deletingLastPathComponent().lastPathComponent == "\(id.rawValue.uuidString).mural")

        let tab = try #require(env.tabs.open(.saved(id), title: "Local"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let model = try #require(tab.session.model)
        let draft = try #require(model.importText("ainda não gravado", as: .text))
        let beforeFlush = try #require(await bridge.localBoard(id))
        #expect(beforeFlush.board.item(id: draft.id) == nil, "a edição não gravada não sobe")
        #expect(beforeFlush.board == tab.session.lastPersistedBoard)
        #expect(beforeFlush.board.items.map(\.id) == [card.id])

        tab.session.captureBoardIfNeeded()
        await tab.session.flushAndPrepareToLeave()
        let afterFlush = try #require(await bridge.localBoard(id))
        #expect(afterFlush.board.item(id: draft.id) != nil, "depois de gravada, sobe")
        await env.finish()
    }

    // MARK: Envio depois de gravar

    @Test("Edição gravada numa aba: em pouco tempo o motor envia e o segundo Mac recebe")
    func localEditIsSentAfterTheSave() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed(items: [Self.note("um")])
        let remote = try await env.putInCloud(id)
        let tab = try #require(env.tabs.open(.saved(id), title: "Aberto"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let model = try #require(tab.session.model)
        let added = try #require(model.importText("escrito aqui", as: .text))

        tab.session.captureBoardIfNeeded()
        await tab.session.flushAndPrepareToLeave()

        await waitUntil("o segundo Mac receber a edição") {
            _ = try? await remote.engine.fetchChanges()
            return await remote.host.board.item(id: added.id) != nil
        }
        await env.finish()
    }

    @Test("Junção pura: o que chegou do iCloud não volta como envio")
    func pureMergeSendsNothing() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(items: [card])
        let remote = try await env.putInCloud(id)
        let tab = try #require(env.tabs.open(.saved(id), title: "Aberto"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: id))
        try await remote.edit { Self.setText(Self.editedText, of: card.id, in: &$0) }
        let before = try await env.cloud.fetchChanges(zone: zone, since: 0, as: CloudSyncController.testUser).token

        await env.controller.fetch()
        // Espera mais que a espera do envio: se a junção agendasse um, ele já teria saído.
        try await Task.sleep(for: SyncEnvironment.sendDelay * 4)
        await env.controller.send()

        #expect(tab.session.model?.board.item(id: card.id)?.text == Self.editedText, "a junção aconteceu")
        let after = try await env.cloud.fetchChanges(zone: zone, since: 0, as: CloudSyncController.testUser).token
        #expect(after == before, "nada subiu ao iCloud")
        await env.finish()
    }

    @Test("Mural só leitura: abre sem edição e ainda recebe o que a dona muda")
    func readOnlyBoardOpensReadOnlyAndStillReceives() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed(name: "Só ver", items: [Self.note("um")], database: .shared, permission: .readOnly)
        let info = try #require(try await env.diskManifest(id).cloud)
        try await env.joinZone(of: info)
        await env.controller.start()
        try await env.controller.track(id, cloud: info)
        let owner = try await RemoteMac.join(
            boardID: id, name: "Só ver", cloud: env.cloud, root: env.directory.appendingPathComponent("Dona"), user: "ana")
        let tab = try #require(env.tabs.open(.saved(id), title: "Só ver"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let model = try #require(tab.session.model)
        #expect(model.isReadOnly)
        #expect(model.importText("não deve entrar", as: .text) == nil)

        let arrived = Self.note("da dona")
        try await owner.edit { $0.add(arrived) }
        await env.controller.fetch()

        #expect(model.board.item(id: arrived.id) != nil, "quem só vê recebe as mudanças")
        #expect(model.isReadOnly)
        await env.finish()
    }

    @Test("Conta trocada com a aba aberta: o disco fica sem cloud, mesmo depois de a aba gravar de novo")
    func accountChangedWithOpenTabKeepsCloudCleared() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed(name: "Aberto", items: [Self.note("um")], database: .private)
        let info = try #require(try await env.diskManifest(id).cloud)
        await env.controller.start()
        try await env.controller.track(id, cloud: info)
        let tab = try #require(env.tabs.open(.saved(id), title: "Aberto"))
        await waitUntil("a aba carregar") { tab.session.model != nil }
        let coordinator = try #require(env.controller.coordinator(for: .private))

        try await coordinator.handleZoneDeleted(
            CloudZoneID(name: info.zoneName, ownerName: info.zoneOwnerName), reason: .accountChanged)

        #expect(try await env.diskManifest(id).cloud == nil)
        let model = try #require(tab.session.model)
        #expect(!model.isReadOnly)
        _ = try #require(model.importText("depois da troca", as: .text))
        tab.session.captureBoardIfNeeded()
        await tab.session.flushAndPrepareToLeave()

        #expect(try await env.diskManifest(id).cloud == nil, "a gravação da aba não devolve o cloud ao disco")
        #expect(try await env.diskBoard(id).items.count == 2)
        #expect(env.controller.notices.count == 1)
        await env.finish()
    }

    // MARK: Pôr no iCloud

    @Test("Pôr no iCloud: cópia em Backups/, cloud no manifesto pela aba aberta, e o segundo Mac recebe o mural")
    func putBoardInCloud() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(name: "Para a nuvem", items: [card])
        await env.controller.start()
        let tab = try #require(env.tabs.open(.saved(id), title: "Para a nuvem"))
        await waitUntil("a aba carregar") { tab.session.model != nil }

        try await env.controller.putInCloud(.saved(id))

        let backups = await env.library.rootDirectory.appendingPathComponent("Backups", isDirectory: true)
        let copies = try FileManager.default.contentsOfDirectory(atPath: backups.path)
        #expect(copies.count == 1)
        #expect(copies.first?.hasPrefix(id.rawValue.uuidString) == true)
        #expect(copies.first?.hasSuffix(".mural") == true)
        #expect(try await env.diskManifest(id).cloud == SyncEnvironment.cloudInfo(database: .private, for: id))
        #expect(try await env.controller.coordinator(for: .private)?.boardIDs() == [id])
        let remote = try await RemoteMac.join(
            boardID: id, name: "Para a nuvem", cloud: env.cloud, root: env.directory.appendingPathComponent("OutroMac"))
        #expect(await remote.host.board.item(id: card.id)?.text == "um")

        // A aba continua dona do manifesto: gravar de novo não tira o cloud.
        let model = try #require(tab.session.model)
        _ = try #require(model.importText("depois", as: .text))
        tab.session.captureBoardIfNeeded()
        await tab.session.flushAndPrepareToLeave()
        #expect(try await env.diskManifest(id).cloud != nil)

        await #expect(throws: CloudSyncControllerError.alreadyInCloud) { try await env.controller.putInCloud(.saved(id)) }
        await #expect(throws: CloudSyncControllerError.notASavedBoard) {
            try await env.controller.putInCloud(.welcomeDraft(BoardID()))
        }
        await env.finish()
    }

    // MARK: Mural removido

    struct RemovalCase: Sendable, CustomTestStringConvertible {
        var database: BoardCloudInfo.Database
        var reason: BoardRemovalReason
        var removesPackage: Bool
        var testDescription: String { "\(database.rawValue), \(reason), \(removesPackage ? "apaga o pacote" : "fica só local")" }
    }

    @Test(
        "Mural que sai do iCloud: o pacote some ou o mural fica só local, conforme o banco e o motivo",
        arguments: [
            RemovalCase(database: .shared, reason: .zoneDeleted, removesPackage: true),
            RemovalCase(database: .shared, reason: .accessRevoked, removesPackage: true),
            RemovalCase(database: .private, reason: .zoneDeleted, removesPackage: true),
            RemovalCase(database: .private, reason: .accountChanged, removesPackage: false),
            RemovalCase(database: .private, reason: .cloudDataErased, removesPackage: false),
        ])
    func removedBoard(_ removal: RemovalCase) async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed(name: "Saindo", items: [Self.note("um")], database: removal.database)
        let info = try #require(try await env.diskManifest(id).cloud)
        let package = try await env.packageURL(of: id)
        try await env.joinZone(of: info)
        await env.controller.start()
        try await env.controller.track(id, cloud: info)
        // Com a aba aberta: o `cloud` sai pela sessão dela, não por baixo.
        let tab = env.tabs.open(.saved(id), title: "Saindo")
        if let tab { await waitUntil("a aba carregar") { tab.session.model != nil } }
        let scope = try #require(CloudDatabaseScope(rawValue: removal.database.rawValue))
        let coordinator = try #require(env.controller.coordinator(for: scope))

        try await coordinator.handleZoneDeleted(
            CloudZoneID(name: info.zoneName, ownerName: info.zoneOwnerName), reason: removal.reason)

        #expect(try await coordinator.boardIDs().isEmpty, "o coordenador parou de acompanhar o mural")
        #expect(env.controller.notices.count == 1)
        #expect(env.controller.notices.first?.message.contains("Saindo") == true)
        if removal.removesPackage {
            #expect(!FileManager.default.fileExists(atPath: package.path))
            #expect(env.tabs.tab(for: id) == nil, "a aba fechou")
            #expect(tab?.session.isClosed == true)
        } else {
            #expect(FileManager.default.fileExists(atPath: package.path), "o pacote fica: só a cópia na nuvem sumiu")
            let snapshot = try #require(try await env.library.open(.saved(id)))
            #expect(snapshot.manifest.cloud == nil)
            #expect(snapshot.board.items.count == 1)
        }
        await env.finish()
    }

    @Test("Zona de mural compartilhado apagada pelo dono: a busca do controlador remove o pacote")
    func sharedZoneDeletedByTheOwner() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed(name: "De outra pessoa", items: [Self.note("um")], database: .shared)
        let info = try #require(try await env.diskManifest(id).cloud)
        let package = try await env.packageURL(of: id)
        try await env.joinZone(of: info)
        await env.controller.start()
        try await env.controller.track(id, cloud: info)
        await env.controller.fetch()
        #expect(FileManager.default.fileExists(atPath: package.path))

        await env.cloud.deleteZone(info.zoneName, owner: info.zoneOwnerName)
        await env.controller.fetch()

        #expect(!FileManager.default.fileExists(atPath: package.path))
        #expect(env.controller.notices.count == 1)
        await env.finish()
    }

    // MARK: Falha de gravação

    @Test("Se a gravação falha, o coordenador marca a busca completa e a busca seguinte limpa o aviso")
    func saveFailureMarksTheBoardUntilTheNextFetch() async throws {
        // A falha injetada vale uma gravação só: a seguinte, a que a sessão avulsa faz ao fechar, passa.
        let env = try SyncEnvironment(faults: BoardRepositoryFaultInjection(points: [.beforeSwap]))
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(items: [card])
        let remote = try await env.putInCloud(id)
        let coordinator = try #require(env.controller.coordinator(for: .private))

        try await remote.edit { Self.setText(Self.editedText, of: card.id, in: &$0) }
        await env.controller.fetch()

        #expect(await coordinator.issues()[id] == .localSaveFailed)
        #expect(env.controller.issues[id] == .localSaveFailed)
        #expect(try await coordinator.zonesNeedingFullFetch().map(\.name) == [CloudSchema.zoneName(for: id)])
        #expect(try await coordinator.boardIDs() == [id], "o mural continua acompanhado")
        #expect(env.liveSessions(of: id).isEmpty)

        await env.controller.fetch()

        #expect(await coordinator.issues().isEmpty)
        #expect(env.controller.issues.isEmpty)
        #expect(try await coordinator.zonesNeedingFullFetch().isEmpty)
        #expect(try await env.diskBoard(id).item(id: card.id)?.text == Self.editedText)
        await env.finish()
    }

    // MARK: Ligar e desligar

    @Test("Sincronização desligada: nenhum motor, e nada é acompanhado")
    func offControllerDoesNothing() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let controller = CloudSyncController(
            mode: .off, registry: env.registry, delivery: env.delivery, directory: env.directory.appendingPathComponent("SyncOff"))

        await controller.start()
        await controller.fetch()
        await controller.send()

        #expect(!controller.isEnabled)
        #expect(controller.coordinator(for: .private) == nil)
        let id = BoardID()
        let info = BoardCloudInfo(database: .private, zoneName: CloudSchema.zoneName(for: id), zoneOwnerName: "x", permission: .owner)
        await #expect(throws: CloudSyncControllerError.disabled) { try await controller.track(id, cloud: info) }
    }

    @Test(
        "Pedir o iCloud de verdade sem o entitlement liga nada: criar o container encerraria o app",
        .enabled(if: !CloudAvailability.hasCloudKitEntitlement))
    func cloudKitWithoutEntitlementStaysOff() throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }

        let controller = CloudSyncController(
            mode: .cloudKit, registry: env.registry, delivery: env.delivery, directory: env.directory.appendingPathComponent("SyncOff"))

        #expect(controller.mode == .off)
        #expect(!controller.isEnabled)
    }

    @Test("start() devolve ao motor o que ficou pendente de uma execução anterior")
    func startRequeuesPendingChangesOfTrackedBoards() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(items: [card])
        let remote = try await env.putInCloud(id)

        // O app foi fechado com uma edição gravada e não enviada: o estado guardado já a tem como pendente.
        var edited = card
        edited.text = "gravado e não enviado"
        try await env.seedLibrary.repository(for: .saved(id)).save(try await env.editedSnapshot(id) { $0.board.update(edited) })
        let restarted = CloudSyncController(
            mode: .inMemory, registry: env.registry, delivery: env.delivery, directory: env.directory.appendingPathComponent("Sync"),
            cloud: env.cloud)
        await restarted.start()
        await restarted.send()

        try await remote.engine.fetchChanges()
        #expect(await remote.host.board.item(id: card.id)?.text == "gravado e não enviado")
    }

    @Test("start() com o iCloud falso vazio não apaga o pacote de um mural privado já acompanhado")
    func startRecreatesTheZoneOfTrackedBoardsInMemory() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        let card = Self.note("um")
        let id = try await env.seed(items: [card])
        _ = try await env.putInCloud(id)
        let package = try await env.packageURL(of: id)
        // Uma edição gravada e não enviada: o envio da nova execução vai à zona, que sem a recriação não existiria (`.zoneMissing`,
        // que o coordenador trata como zona apagada e remove o pacote).
        var edited = card
        edited.text = "gravado e não enviado"
        try await env.seedLibrary.repository(for: .saved(id)).save(try await env.editedSnapshot(id) { $0.board.update(edited) })

        // Outra execução do app (`-uiTestingKeep`): o pacote e o estado de sincronização ficaram, o iCloud falso nasceu vazio.
        let emptyCloud = InMemoryCloud()
        let restarted = CloudSyncController(
            mode: .inMemory, registry: env.registry, delivery: env.delivery, directory: env.directory.appendingPathComponent("Sync"),
            cloud: emptyCloud)
        await restarted.start()
        await restarted.send()
        await restarted.fetch()

        #expect(FileManager.default.fileExists(atPath: package.path), "a zona recriada não conta como apagada")
        #expect(restarted.notices.isEmpty)
        #expect(try await env.diskManifest(id).cloud != nil)
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: id))
        let sent = try await emptyCloud.fetchChanges(zone: zone, since: 0, as: CloudSyncController.testUser)
        #expect(!sent.saved.isEmpty, "o envio chegou à zona recriada")
    }

    @Test("O controlador sai da memória: a ponte não o segura")
    func controllerIsReleased() async throws {
        let env = try SyncEnvironment()
        defer { env.removeFiles() }
        weak var released: CloudSyncController?

        do {
            let controller = CloudSyncController(
                mode: .inMemory, registry: env.registry, delivery: env.delivery, directory: env.directory.appendingPathComponent("SyncTemp")
            )
            released = controller
            await controller.start()
            await controller.fetch()
        }
        for _ in 0..<10 { await Task.yield() }

        #expect(released == nil)
    }

    // MARK: Configuração

    @Test("A configuração: iCloud falso nos testes de interface, o de verdade só com o entitlement e fora dos testes unitários")
    func launchConfigurationChoosesTheCloud() {
        let plain: [String: String] = [:]
        let unitTests = ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"]
        #expect(LaunchConfiguration.cloudSync(arguments: ["-uiTesting"], environment: plain, hasCloudKitEntitlement: false) == .inMemory)
        #expect(
            LaunchConfiguration.cloudSync(arguments: ["-uiTestingKeep"], environment: plain, hasCloudKitEntitlement: false) == .inMemory)
        #expect(LaunchConfiguration.cloudSync(arguments: ["-uiTesting"], environment: plain, hasCloudKitEntitlement: true) == .inMemory)
        #expect(LaunchConfiguration.cloudSync(arguments: [], environment: plain, hasCloudKitEntitlement: true) == .cloudKit)
        #expect(LaunchConfiguration.cloudSync(arguments: [], environment: plain, hasCloudKitEntitlement: false) == .off)
        #expect(LaunchConfiguration.cloudSync(arguments: ["-manualTesting"], environment: plain, hasCloudKitEntitlement: false) == .off)
        #expect(
            LaunchConfiguration.cloudSync(arguments: [], environment: unitTests, hasCloudKitEntitlement: true) == .off,
            "o app que hospeda os testes unitários não toca a conta iCloud real")
        #expect(
            LaunchConfiguration.cloudSync(
                arguments: ["-manualTesting", "-performanceFixture"], environment: plain, hasCloudKitEntitlement: true) == .off,
            "o perfil de desempenho mede o app sem o iCloud")
        #expect(
            LaunchConfiguration.cloudSync(arguments: ["-manualTesting"], environment: plain, hasCloudKitEntitlement: true)
                == .cloudKit)
    }

    @Test("O entitlement vale só se a lista de serviços do iCloud traz CloudKit")
    func entitlementValueMustListCloudKit() {
        #expect(CloudAvailability.listsCloudKit(["CloudKit", "CloudDocuments"]))
        #expect(!CloudAvailability.listsCloudKit(["CloudDocuments"]))
        #expect(!CloudAvailability.listsCloudKit([String]()))
        #expect(!CloudAvailability.listsCloudKit("CloudKit"))
        #expect(!CloudAvailability.listsCloudKit(nil))
        _ = CloudAvailability.hasCloudKitEntitlement  // a leitura do processo não pode encerrar o app
    }
}

// MARK: Apoio

/// Anota o que o teste quer ver de dentro de `onPersisted`.
@MainActor
private final class PersistRecorder {
    var fileExistedWhenCardWasSaved: [Bool] = []
}

/// Biblioteca temporária, abas, entrega e controlador, ligados como no app, com o iCloud falso.
@MainActor
private final class SyncEnvironment {
    /// A espera entre gravar e enviar nos testes, bem menor que a de uso (1 s).
    static let sendDelay: Duration = .milliseconds(100)

    let directory: URL
    /// A biblioteca com que o teste monta o mural (sem falhas); `library` é a do app, que pode ter a falha injetada.
    let seedLibrary: BoardLibrary
    let library: BoardLibrary
    let registry: BoardSessionRegistry
    let delivery: BoardDelivery
    let tabs: MuralTabs
    let cloud: InMemoryCloud
    let controller: CloudSyncController

    init(faults: BoardRepositoryFaultInjection = .none) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralCloudSync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let root = directory.appendingPathComponent("Biblioteca", isDirectory: true)
        // Mural excluído nos testes é apagado, não vai para o Lixo de quem roda os testes.
        let discard: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
        let library = BoardLibrary(rootDirectory: root, repositoryFaultInjection: faults, discardPackage: discard)
        let registry = BoardSessionRegistry(library: library)
        let makeSession: @MainActor (BoardRoute) -> BoardWindowSession = {
            BoardWindowSession(route: $0, registry: registry, usesOnDeviceModel: false)
        }
        let delivery = BoardDelivery(registry: registry, covers: nil, makeSession: makeSession)
        let tabs = MuralTabs(
            registry: registry, makeSession: { route in delivery.adoptDetachedSession(for: route) ?? makeSession(route) })
        tabs.removeBoardCaches = { _ in }
        tabs.dockPresence = { _ in }
        delivery.tabs = tabs
        let cloud = InMemoryCloud()

        self.directory = directory
        self.cloud = cloud
        self.seedLibrary = BoardLibrary(rootDirectory: root, discardPackage: discard)
        self.library = library
        self.registry = registry
        self.delivery = delivery
        self.tabs = tabs
        self.controller = CloudSyncController(
            mode: .inMemory, registry: registry, delivery: delivery, directory: directory.appendingPathComponent("Sync"),
            cloud: cloud, sendDelay: Self.sendDelay)
    }

    func bridge() -> CloudSyncBridge {
        CloudSyncBridge(scope: .private, registry: registry, delivery: delivery, notify: { _ in })
    }

    // MARK: Murais

    /// Cria um mural salvo com os cartões dados, já gravado, e com o `cloud` do banco pedido no manifesto.
    func seed(
        name: String = "Compartilhado", items: [BoardItem], database: BoardCloudInfo.Database? = nil,
        permission: BoardCloudInfo.Permission? = nil
    ) async throws -> BoardID {
        let route = try await seedLibrary.createNamedBoard(name)
        var snapshot = try #require(try await seedLibrary.open(route))
        let id = snapshot.manifest.id
        for item in items { snapshot.board.add(item) }
        if !items.isEmpty { snapshot.manifest.contentRevision += 1 }
        snapshot.manifest.cloud = database.map { Self.cloudInfo(database: $0, for: id, permission: permission) }
        try await seedLibrary.repository(for: route).save(snapshot)
        return id
    }

    /// O mural de `id` regravado com a mudança, para simular uma gravação feita antes de o app fechar.
    func editedSnapshot(_ id: BoardID, _ change: (inout BoardRepositorySnapshot) -> Void) async throws -> BoardRepositorySnapshot {
        var snapshot = try #require(try await seedLibrary.open(.saved(id)))
        change(&snapshot)
        snapshot.manifest.contentRevision += 1
        return snapshot
    }

    nonisolated static func cloudInfo(
        database: BoardCloudInfo.Database, for id: BoardID, permission: BoardCloudInfo.Permission? = nil
    ) -> BoardCloudInfo {
        switch database {
        case .private:
            BoardCloudInfo(
                database: .private, zoneName: CloudSchema.zoneName(for: id), zoneOwnerName: CloudZoneID.defaultOwnerName,
                permission: .owner)
        case .shared:
            BoardCloudInfo(
                database: .shared, zoneName: CloudSchema.zoneName(for: id), zoneOwnerName: "ana", ownerDisplayName: "Ana",
                permission: permission ?? .readWrite)
        }
    }

    /// No banco compartilhado a zona é de outra pessoa, que a deu a este usuário; no privado, o motor a cria em `track`.
    func joinZone(of info: BoardCloudInfo) async throws {
        guard info.database == .shared else { return }
        await cloud.createZone(info.zoneName, owner: info.zoneOwnerName)
        try await cloud.share(
            zone: info.zoneName, owner: info.zoneOwnerName, with: CloudSyncController.testUser,
            permission: info.permission == .readOnly ? .readOnly : .readWrite)
    }

    /// Acompanha o mural no banco privado, manda tudo ao iCloud e põe o segundo Mac para acompanhá-lo também.
    func putInCloud(_ id: BoardID) async throws -> RemoteMac {
        let info = Self.cloudInfo(database: .private, for: id)
        var snapshot = try #require(try await seedLibrary.open(.saved(id)))
        snapshot.manifest.cloud = info
        try await seedLibrary.repository(for: .saved(id)).save(snapshot)
        await controller.start()
        try await controller.track(id, cloud: info)
        return try await RemoteMac.join(
            boardID: id, name: snapshot.manifest.name, cloud: cloud, root: directory.appendingPathComponent("OutroMac"))
    }

    // MARK: Conferir

    func diskBoard(_ id: BoardID) async throws -> Board {
        try #require(try await library.readBoard(.saved(id)))
    }

    func diskManifest(_ id: BoardID) async throws -> BoardManifest {
        try #require(try await library.open(.saved(id))).manifest
    }

    func packageURL(of id: BoardID) async throws -> URL {
        try await library.repository(for: .saved(id)).packageURL(for: id)
    }

    func itemsDirectory(of id: BoardID) async throws -> URL {
        try await BoardStore(directory: packageURL(of: id)).itemsDirectory
    }

    func liveSessions(of id: BoardID) -> [BoardWindowSession] {
        OpenBoardSessions.shared.live.filter { $0.boardID == id }
    }

    /// Fecha as abas (gravando).
    func finish() async {
        await tabs.closeAll()
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// O host do segundo Mac: guarda o mural em memória e junta o que chega com `BoardMerge.apply`, como o app de verdade faz.
private actor RemoteMacHost: BoardSyncHost {
    private(set) var board = Board()
    private var name: String
    private let itemsDirectory: URL

    init(name: String, itemsDirectory: URL) {
        self.name = name
        self.itemsDirectory = itemsDirectory
    }

    func replace(_ board: Board) {
        self.board = board
    }

    func localBoard(_ id: BoardID) -> LocalBoardSnapshot? {
        LocalBoardSnapshot(name: name, board: board, itemsDirectory: itemsDirectory)
    }

    func applyRemote(_ id: BoardID, received: ReceivedChanges) async throws {
        board = BoardMerge.apply(received.changes, to: board, base: received.previousBase).board
        name = received.mergedName(local: name)
        for (file, source) in received.files {
            let destination = itemsDirectory.appendingPathComponent(file, isDirectory: false)
            if !FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.copyItem(at: source, to: destination) }
        }
    }

    func boardRemoved(_ id: BoardID, reason: BoardRemovalReason) {}
}

/// O segundo Mac do mesmo usuário: outro coordenador e outro motor falso sobre o mesmo iCloud falso.
private struct RemoteMac {
    let host: RemoteMacHost
    let coordinator: BoardSyncCoordinator
    let engine: InMemorySyncEngine
    let boardID: BoardID
    let items: URL

    /// Passa a acompanhar o mural na zona do usuário e busca o que o primeiro Mac já enviou. Não envia nada: só recebe.
    static func join(
        boardID: BoardID, name: String, cloud: InMemoryCloud, root: URL, user: String = CloudSyncController.testUser
    ) async throws -> RemoteMac {
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        let host = RemoteMacHost(name: name, itemsDirectory: items)
        let store = SyncMetadataStore(directory: root.appendingPathComponent("Sync", isDirectory: true))
        let coordinator = BoardSyncCoordinator(scope: .private, store: store, host: host)
        let engine = InMemorySyncEngine(user: user, scope: .private, cloud: cloud, coordinator: coordinator)
        _ = try await coordinator.startTracking(boardID, cloud: SyncEnvironment.cloudInfo(database: .private, for: boardID))
        try await engine.fetchChanges()
        return RemoteMac(host: host, coordinator: coordinator, engine: engine, boardID: boardID, items: items)
    }

    func writeFile(_ name: String, contents: String) throws {
        try Data(contents.utf8).write(to: items.appendingPathComponent(name))
    }

    /// Uma edição neste Mac, enviada ao iCloud na hora.
    func edit(_ change: (inout Board) -> Void) async throws {
        var board = await host.board
        change(&board)
        await host.replace(board)
        await engine.add(try await coordinator.pendingChanges(for: boardID))
        try await engine.sendChanges()
    }
}
