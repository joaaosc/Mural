import Foundation
import MuralKit
import Testing

@testable import Mural

/// As cópias dos murais na pasta Mural do iCloud Drive. Uma pasta temporária faz o papel do iCloud Drive e o Lixo vira uma remoção
/// simples: nenhum teste toca o iCloud Drive nem o Lixo de quem os roda.
@Suite("Cópias no iCloud Drive", .serialized)
@MainActor
struct DriveMirrorTests {
    // MARK: Passada

    @Test("Mural só deste Mac ganha cópia na pasta, com os três JSON e Items/, e o manifesto não leva cloud")
    func localBoardGetsACopy() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed("Viagem")
        let controller = env.makeController()
        #expect(!FileManager.default.fileExists(atPath: env.documents.path), "a pasta ainda não existe")

        await controller.reconcileNow()

        #expect(env.copyNames() == ["Viagem.mural"], "o espelho criou a pasta")
        let copy = env.package(named: "Viagem")
        for file in ["manifest.json", "board.json", "view-state.json"] {
            #expect(FileManager.default.fileExists(atPath: copy.appendingPathComponent(file).path), "falta \(file)")
        }
        var isDirectory: ObjCBool = false
        let hasItems = FileManager.default.fileExists(atPath: copy.appendingPathComponent("Items").path, isDirectory: &isDirectory)
        #expect(hasItems && isDirectory.boolValue, "falta Items/")
        let manifest = try env.copyManifest("Viagem")
        #expect(manifest.id == id)
        #expect(manifest.cloud == nil)
        let stored = try #require(try await env.library.open(.saved(id))).manifest
        #expect(controller.lastWritten[id] == DriveMirrorController.Mark(stored))
        #expect(env.transferLeftovers.isEmpty, "a pasta de passagem sai")
    }

    @Test("Só os murais da própria pessoa ganham cópia: os recebidos e os que esperam a primeira busca, não")
    func onlyTheOwnBoardsAreCopied() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        try await env.seed("Meu")
        try await env.seed("Na nuvem", database: .private)
        try await env.seed("Recebido", database: .shared)
        let waiting = try await env.seed("Esperando", database: .private)
        env.awaiting = [waiting]
        let controller = env.makeController()

        await controller.reconcileNow()

        #expect(env.copyNames() == ["Meu.mural", "Na nuvem.mural"])
        #expect(try env.copyManifest("Na nuvem").cloud == nil, "a cópia é só uma cópia: sem cloud")

        env.awaiting = []
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Esperando.mural", "Meu.mural", "Na nuvem.mural"], "com o conteúdo, a cópia vem")
    }

    @Test("boardChanged depois de mudar o conteúdo regrava a cópia; sem mudança de conteúdo nem de nome, não regrava")
    func changeRewritesOnlyWhenTheContentOrTheNameChanged() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed("Diario")
        let controller = env.makeController()
        await controller.reconcileNow()
        // Uma marca no board.json da cópia mostra se a passada o regravou.
        let json = env.boardJSON("Diario")
        let marked = try Data(contentsOf: json) + Data(" ".utf8)
        try marked.write(to: json)

        controller.boardChanged(id)
        #expect(controller.pendingWrites == [id])
        await controller.reconcileNow()
        #expect(try Data(contentsOf: json) == marked, "mesmo conteúdo e mesmo nome: a cópia não é regravada")
        #expect(controller.pendingWrites.isEmpty, "o aviso sai mesmo assim")

        try await env.edit(id)
        controller.boardChanged(id)
        await controller.reconcileNow()
        #expect(try Data(contentsOf: json) != marked, "conteúdo novo: a cópia é regravada")
        let revision = try #require(try await env.library.open(.saved(id))).manifest.contentRevision
        #expect(try env.copyManifest("Diario").contentRevision == revision)
        #expect(controller.pendingWrites.isEmpty)
        #expect(controller.lastWritten[id]?.contentRevision == revision)
    }

    @Test("Renomear o mural muda o nome da cópia, e com o aviso o manifesto dela traz o nome novo")
    func renameMovesTheCopy() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed("Antes")
        let controller = env.makeController()
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Antes.mural"])

        _ = try await env.library.rename(.saved(id), to: "Depois")
        controller.libraryChanged()
        controller.boardChanged(id)
        await controller.reconcileNow()

        #expect(env.copyNames() == ["Depois.mural"], "o mesmo pacote mudou de nome, sem ficar uma segunda cópia")
        #expect(try env.copyManifest("Depois").name == "Depois")
        #expect(controller.lastWritten[id]?.name == "Depois")
        #expect(controller.pendingWrites.isEmpty)
    }

    @Test("boardDeletedByUser leva a cópia ao Lixo; o mural que some da biblioteca sem o aviso mantém a cópia")
    func onlyTheUsersDeletionTrashesTheCopy() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let deleted = try await env.seed("Excluido")
        let vanished = try await env.seed("Sumiu")
        try await env.seed("Fica")
        let controller = env.makeController()
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Excluido.mural", "Fica.mural", "Sumiu.mural"])

        try await env.library.deleteBoard(.saved(deleted))
        try await env.library.deleteBoard(.saved(vanished))
        controller.boardDeletedByUser(deleted)
        #expect(controller.pendingTrash == [deleted])
        await controller.reconcileNow()

        #expect(env.copyNames() == ["Fica.mural", "Sumiu.mural"], "só a exclusão avisada leva a cópia")
        #expect(controller.pendingTrash.isEmpty)
        #expect(controller.lastWritten[deleted] == nil)
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Fica.mural", "Sumiu.mural"], "sem o aviso, a cópia do que sumiu fica")

        controller.boardDeletedByUser(BoardID())
        await controller.reconcileNow()
        #expect(controller.pendingTrash.isEmpty, "exclusão sem cópia na pasta não fica pendente")
    }

    @Test("Opção desligada: nada é escrito nem apagado; religada, a passada escreve")
    func disabledOptionDoesNothing() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed("Um")
        let controller = env.makeController()
        #expect(controller.isEnabled, "ligada por padrão")

        controller.isEnabled = false
        #expect(env.defaults.object(forKey: DriveMirrorController.enabledKey) as? Bool == false)
        #expect(!env.makeController().isEnabled, "a opção vale para o controlador seguinte")
        controller.boardChanged(id)
        await controller.reconcileNow()
        #expect(env.copyNames().isEmpty)
        #expect(controller.pendingWrites == [id], "o aviso fica anotado")

        controller.isEnabled = true
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Um.mural"])

        controller.isEnabled = false
        try await env.library.deleteBoard(.saved(id))
        controller.boardDeletedByUser(id)
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Um.mural"], "desligar não apaga as cópias que já existem")
        controller.isEnabled = true
        await controller.reconcileNow()
        #expect(env.copyNames().isEmpty, "religada, a exclusão que ficou anotada sai")
    }

    @Test("Sem iCloud Drive nada acontece e as pendências ficam até ele voltar")
    func unavailableICloudDriveKeepsThePending() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let kept = try await env.seed("Fica")
        let gone = try await env.seed("Foi")
        let controller = env.makeController()
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Fica.mural", "Foi.mural"])

        env.isAvailable = false
        try await env.edit(kept)
        try await env.library.deleteBoard(.saved(gone))
        controller.boardChanged(kept)
        controller.boardDeletedByUser(gone)
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Fica.mural", "Foi.mural"])
        #expect(controller.pendingWrites == [kept])
        #expect(controller.pendingTrash == [gone])

        env.isAvailable = true
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Fica.mural"])
        let revision = try #require(try await env.library.open(.saved(kept))).manifest.contentRevision
        #expect(try env.copyManifest("Fica").contentRevision == revision)
        #expect(controller.pendingWrites.isEmpty && controller.pendingTrash.isEmpty)
    }

    @Test("Erro numa ação não impede as outras: o mural segue pendente e a pasta de passagem fica limpa")
    func aFailedWriteKeepsTheBoardPending() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let blocked = try await env.seed("Travado")
        try await env.seed("Livre")
        // Um arquivo comum no lugar do pacote: a gravação desse mural falha.
        try FileManager.default.createDirectory(at: env.documents, withIntermediateDirectories: true)
        let obstacle = env.package(named: "Travado")
        try Data("arquivo, não pacote".utf8).write(to: obstacle)
        let controller = env.makeController()
        controller.boardChanged(blocked)

        await controller.reconcileNow()

        #expect(try env.copyManifest("Livre").name == "Livre", "a outra cópia saiu")
        #expect(controller.pendingWrites == [blocked])
        #expect(controller.lastWritten[blocked] == nil)
        #expect(env.transferLeftovers.isEmpty, "a pasta de passagem sai também no erro")

        try FileManager.default.removeItem(at: obstacle)
        await controller.reconcileNow()
        #expect(try env.copyManifest("Travado").id == blocked)
        #expect(controller.pendingWrites.isEmpty)
    }

    // MARK: Estado

    @Test("O estado sobrevive a um controlador novo na mesma pasta, e a passada seguinte o usa")
    func stateSurvivesANewController() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        try await env.seed("Escrito")
        let pending = try await env.seed("Pendente")
        let deleted = try await env.seed("Excluido")
        let first = env.makeController()
        await first.reconcileNow()
        try await env.edit(pending)
        first.boardChanged(pending)
        try await env.library.deleteBoard(.saved(deleted))
        first.boardDeletedByUser(deleted)

        let second = env.makeController()

        #expect(second.pendingWrites == [pending])
        #expect(second.pendingTrash == [deleted])
        #expect(!second.lastWritten.isEmpty)
        #expect(second.lastWritten == first.lastWritten)
        await second.reconcileNow()
        #expect(env.copyNames() == ["Escrito.mural", "Pendente.mural"])
        let revision = try #require(try await env.library.open(.saved(pending))).manifest.contentRevision
        #expect(try env.copyManifest("Pendente").contentRevision == revision)
    }

    @Test("Trocar de conta do iCloud zera o que o Mac anotou, e a passada seguinte copia tudo de novo")
    func accountChangeStartsOver() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let id = try await env.seed("Um")
        let controller = env.makeController()
        await controller.reconcileNow()
        controller.boardChanged(id)
        controller.boardDeletedByUser(BoardID())
        #expect(!controller.lastWritten.isEmpty)

        controller.accountDidChange()

        #expect(controller.pendingWrites.isEmpty && controller.pendingTrash.isEmpty && controller.lastWritten.isEmpty)
        #expect(env.makeController().lastWritten.isEmpty, "o estado gravado também foi zerado")
        try FileManager.default.removeItem(at: env.documents)  // a conta nova tem a pasta vazia
        await controller.reconcileNow()
        #expect(env.copyNames() == ["Um.mural"])
    }

    // MARK: Agenda

    @Test("Avisos seguidos viram uma passada só, que roda sozinha depois da espera")
    func noticesInARowBecomeOnePass() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let first = try await env.seed("Um")
        let second = try await env.seed("Dois")
        let controller = env.makeController(delay: .milliseconds(200))

        controller.boardChanged(first)
        controller.boardChanged(second)
        controller.libraryChanged()
        #expect(env.passes == 0, "a passada espera")
        await waitUntil("a passada rodar") { env.copyNames().count == 2 }

        try await Task.sleep(for: .milliseconds(600))
        #expect(env.passes == 1, "uma passada só para os três avisos")
        #expect(controller.pendingWrites.isEmpty)
    }

    @Test("Aviso durante uma passada em andamento agenda outra passada depois dela")
    func noticeDuringAPassSchedulesAnother() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        try await env.seed("Um")
        let controller = env.makeController(delay: .milliseconds(100))
        env.onPassStart = { [unowned env] in
            env.onPassStart = nil
            controller.libraryChanged()  // chega com a primeira passada em andamento
        }

        await controller.reconcileNow()
        #expect(env.passes == 1)

        await waitUntil("a segunda passada") { env.passes == 2 }
        #expect(env.passes == 2)
    }

    @Test("start() agenda a primeira passada para depois do lançamento, uma vez só")
    func startSchedulesTheFirstPass() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        try await env.seed("Um")
        let controller = env.makeController(launchDelay: .milliseconds(50))

        controller.start()
        controller.start()
        await waitUntil("a primeira passada") { env.copyNames() == ["Um.mural"] }

        try await Task.sleep(for: .milliseconds(300))
        #expect(env.passes == 1)
    }

    // MARK: O espelho

    @Test("O espelho recusa nome que não é de pacote .mural, sem tocar em nada")
    func mirrorRejectsInvalidNames() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let mirror = env.makeMirror()
        try FileManager.default.createDirectory(at: env.documents, withIntermediateDirectories: true)
        let outside = env.directory.appendingPathComponent("fora.mural", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)

        for name in ["../fora.mural", "a/b.mural", "texto.txt", ".mural", ".oculto.mural", "sem-extensao"] {
            await #expect(throws: DriveMirrorError.invalidFileName(name)) { try await mirror.trash(name) }
        }
        await #expect(throws: DriveMirrorError.invalidFileName("../b.mural")) {
            try await mirror.move(from: "a.mural", to: "../b.mural")
        }
        await #expect(throws: DriveMirrorError.invalidFileName("x")) { _ = try await mirror.write(env.directory, as: "x") }
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test("O espelho lê a pasta, renomeia sem sobrescrever e leva ao Lixo; sem iCloud Drive lança unavailable")
    func mirrorScansMovesAndTrashes() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let first = try await env.seed("Um")
        let second = try await env.seed("Dois")
        let controller = env.makeController()
        await controller.reconcileNow()
        let folder = env.documents
        // Entre as cópias: um pacote ilegível, um arquivo comum com o nome de pacote, uma pasta oculta e outra que não é pacote.
        try FileManager.default.createDirectory(at: env.package(named: "Quebrado"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: env.package(named: "Arquivo"))
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent(".Oculto.mural", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Outra pasta", isDirectory: true), withIntermediateDirectories: true)
        let mirror = env.makeMirror()

        let found = try await mirror.scan()
        let expected: [String: BoardID?] = ["Um.mural": first, "Dois.mural": second, "Quebrado.mural": nil]
        #expect(found == expected)

        await #expect(throws: (any Error).self) { try await mirror.move(from: "Um.mural", to: "Dois.mural") }
        #expect(try env.copyManifest("Um").id == first && env.copyManifest("Dois").id == second, "nada foi sobrescrito")
        try await mirror.move(from: "Um.mural", to: "Primeiro.mural")
        #expect(try env.copyManifest("Primeiro").id == first)
        #expect(!FileManager.default.fileExists(atPath: env.package(named: "Um").path))

        try await mirror.trash("Primeiro.mural")
        #expect(!FileManager.default.fileExists(atPath: env.package(named: "Primeiro").path))

        let unavailable = DriveMirror(documents: { nil }, discard: { _ in })
        await #expect(throws: DriveMirrorError.unavailable) { _ = try await unavailable.scan() }
        await #expect(throws: DriveMirrorError.unavailable) { try await unavailable.trash("a.mural") }
    }

    @Test("O espelho nunca grava sobre a pasta de outro mural, e o manifesto de uma cópia se lê fora do Main Actor")
    func mirrorKeepsAnotherBoardsPackage() async throws {
        let env = try DriveMirrorEnvironment()
        defer { env.removeFiles() }
        let first = try await env.seed("Um")
        let second = try await env.seed("Dois")
        let controller = env.makeController()
        await controller.reconcileNow()
        let mirror = env.makeMirror()
        let staging = try await env.library.exportPackage(.saved(first))

        await #expect(throws: BoardPackageMirrorError.destinationIsAnotherBoard(second)) {
            _ = try await mirror.write(staging, as: "Dois.mural")
        }
        let outcome = try await mirror.write(staging, as: "Um.mural")
        #expect(!outcome.changedAnything, "a cópia já estava igual")
        try await env.library.cleanupTransfer(staging)

        #expect(try env.copyManifest("Dois").id == second)
        let manifest = await DriveMirror.manifest(ofPackageAt: env.package(named: "Um"))
        #expect(manifest?.id == first)
        #expect(await DriveMirror.manifest(ofPackageAt: env.package(named: "Inexistente")) == nil)
    }

    // MARK: Configuração

    @Test("A configuração: cópias desligadas nos testes, no perfil manual e no de desempenho; ligadas só com o entitlement do iCloud Drive")
    func launchConfigurationChoosesTheMirror() {
        let plain: [String: String] = [:]
        let unitTests = ["XCTestConfigurationFilePath": "/tmp/config.xctestconfiguration"]
        #expect(LaunchConfiguration.mirrorsToICloudDrive(arguments: [], environment: plain, hasCloudDocumentsEntitlement: true))
        #expect(!LaunchConfiguration.mirrorsToICloudDrive(arguments: [], environment: plain, hasCloudDocumentsEntitlement: false))
        for argument in ["-uiTesting", "-uiTestingKeep", "-manualTesting", "-performanceFixture"] {
            #expect(
                !LaunchConfiguration.mirrorsToICloudDrive(
                    arguments: [argument], environment: plain, hasCloudDocumentsEntitlement: true),
                "\(argument) não toca o iCloud Drive")
        }
        #expect(
            !LaunchConfiguration.mirrorsToICloudDrive(
                arguments: ["-manualTesting", "-performanceFixture"], environment: plain, hasCloudDocumentsEntitlement: true))
        #expect(
            !LaunchConfiguration.mirrorsToICloudDrive(arguments: [], environment: unitTests, hasCloudDocumentsEntitlement: true),
            "o app que hospeda os testes unitários não toca o iCloud Drive de quem os roda")
    }

    @Test("O entitlement vale só se a lista de serviços do iCloud traz CloudDocuments")
    func entitlementValueMustListCloudDocuments() {
        #expect(CloudAvailability.listsCloudDocuments(["CloudKit", "CloudDocuments"]))
        #expect(!CloudAvailability.listsCloudDocuments(["CloudKit"]))
        #expect(!CloudAvailability.listsCloudDocuments([String]()))
        #expect(!CloudAvailability.listsCloudDocuments("CloudDocuments"))
        #expect(!CloudAvailability.listsCloudDocuments(nil))
        _ = CloudAvailability.hasCloudDocumentsEntitlement  // a leitura do processo não pode encerrar o app
    }
}

// MARK: Apoio

/// Biblioteca temporária, pasta do "iCloud Drive" temporária e opções próprias, ligadas como no app.
@MainActor
private final class DriveMirrorEnvironment {
    let directory: URL
    /// No lugar da pasta Documents do iCloud Drive; só passa a existir quando o espelho a cria.
    let documents: URL
    let library: BoardLibrary
    let defaults: UserDefaults
    /// A raiz da biblioteca temporária (a de `library`).
    private let libraryRoot: URL
    private let suiteName: String
    /// O que `isAvailable` responde (conta com iCloud Drive).
    var isAvailable = true
    /// O que `awaitingFirstFetch` responde.
    var awaiting: Set<BoardID> = []
    /// Quantas passadas começaram: o controlador pergunta `isAvailable` uma vez no começo de cada uma.
    private(set) var passes = 0
    /// Roda no começo da próxima passada.
    var onPassStart: (() -> Void)?

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralDriveMirror-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        self.directory = directory
        self.documents = directory.appendingPathComponent("iCloud Drive", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
        let libraryRoot = directory.appendingPathComponent("Biblioteca", isDirectory: true)
        self.libraryRoot = libraryRoot
        // Mural excluído nos testes é apagado, não vai para o Lixo de quem roda os testes.
        self.library = BoardLibrary(rootDirectory: libraryRoot, discardPackage: { try FileManager.default.removeItem(at: $0) })
        let suiteName = "MuralDriveMirrorTests-\(UUID().uuidString)"
        self.suiteName = suiteName
        self.defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// O espelho sobre a pasta temporária, com a remoção no lugar do Lixo.
    func makeMirror() -> DriveMirror {
        let documents = self.documents
        return DriveMirror(documents: { documents }, discard: { try FileManager.default.removeItem(at: $0) })
    }

    /// Um controlador deste "Mac": os de um mesmo ambiente dividem a pasta do estado e as opções, como duas execuções do app.
    func makeController(delay: Duration = .seconds(60), launchDelay: Duration = .seconds(60)) -> DriveMirrorController {
        DriveMirrorController(
            library: library, mirror: makeMirror(), awaitingFirstFetch: { [self] in awaiting },
            isAvailable: { [self] in startPass() }, defaults: defaults,
            stateDirectory: directory.appendingPathComponent("Estado", isDirectory: true), delay: delay, launchDelay: launchDelay)
    }

    private func startPass() -> Bool {
        passes += 1
        onPassStart?()
        return isAvailable
    }

    // MARK: Murais

    /// Cria um mural salvo com um cartão e, se pedido, o `cloud` do banco dado no manifesto.
    @discardableResult
    func seed(_ name: String, database: BoardCloudInfo.Database? = nil) async throws -> BoardID {
        let route = try await library.createNamedBoard(name)
        var snapshot = try #require(try await library.open(route))
        let id = snapshot.manifest.id
        snapshot.board.add(Self.note("um"))
        snapshot.manifest.contentRevision += 1
        snapshot.manifest.cloud = database.map { Self.cloud($0, for: id) }
        try await library.repository(for: route).save(snapshot)
        return id
    }

    /// Muda o conteúdo como uma gravação do app: um cartão novo e `contentRevision` maior.
    func edit(_ id: BoardID, adding text: String = "outro") async throws {
        var snapshot = try #require(try await library.open(.saved(id)))
        snapshot.board.add(Self.note(text))
        snapshot.manifest.contentRevision += 1
        try await library.repository(for: .saved(id)).save(snapshot)
    }

    private static func note(_ text: String) -> BoardItem {
        BoardItem(
            kind: .sticky, title: ContentClassifier.title(forText: text), createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            position: BoardPoint(x: 10, y: 20), text: text, stickyColor: .yellow)
    }

    private static func cloud(_ database: BoardCloudInfo.Database, for id: BoardID) -> BoardCloudInfo {
        switch database {
        case .private:
            BoardCloudInfo(database: .private, zoneName: id.rawValue.uuidString, zoneOwnerName: "dono", permission: .owner)
        case .shared:
            BoardCloudInfo(
                database: .shared, zoneName: id.rawValue.uuidString, zoneOwnerName: "ana", ownerDisplayName: "Ana",
                permission: .readWrite)
        }
    }

    // MARK: Conferir

    /// O pacote `<nome>.mural` na pasta.
    func package(named name: String) -> URL {
        documents.appendingPathComponent("\(name).mural", isDirectory: true)
    }

    func boardJSON(_ name: String) -> URL {
        package(named: name).appendingPathComponent("board.json", isDirectory: false)
    }

    func copyManifest(_ name: String) throws -> BoardManifest {
        try BoardPackageMirror.manifest(ofPackageAt: package(named: name))
    }

    /// Os `*.mural` que há na pasta, em ordem.
    func copyNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: documents.path)) ?? []).filter { $0.hasSuffix(".mural") }.sorted()
    }

    /// O que sobrou na pasta de passagem da biblioteca.
    var transferLeftovers: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: libraryRoot.appendingPathComponent("Transfers").path)) ?? []
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
