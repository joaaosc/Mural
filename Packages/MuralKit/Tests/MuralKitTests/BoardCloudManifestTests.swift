import Foundation
import Testing

@testable import MuralKit

@Suite("Mural compartilhado: o manifest guarda o iCloud")
struct BoardCloudManifestTests {
    /// Mural de outra pessoa, recebido por convite e só para ver.
    private static let receivedInfo = BoardCloudInfo(
        database: .shared, zoneName: "Mural-5B0F4C2E", zoneOwnerName: "_d41d8cd98f00b204e9800998ecf8427e", ownerDisplayName: "Ana",
        permission: .readOnly)

    /// Mural da própria pessoa: banco privado, zona dela e nenhum nome para mostrar.
    private static let ownInfo = BoardCloudInfo(
        database: .private, zoneName: "Mural-5B0F4C2E", zoneOwnerName: "__defaultOwner__", permission: .owner)

    /// As chaves que o manifest sempre teve.
    private static let plainKeys: Set<String> = [
        "contentRevision", "createdAt", "id", "name", "schemaVersion", "updatedAt", "workspaceRevision",
    ]

    /// O `manifest.json` como a build 0.9.6 o grava (chaves em ordem, datas em segundos de referência).
    private static let manifestJSONFrom096 = """
        {
          "contentRevision" : 12,
          "createdAt" : 779000000.25,
          "id" : {
            "rawValue" : "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01"
          },
          "name" : "Casa",
          "schemaVersion" : 1,
          "updatedAt" : 780000000.5,
          "workspaceRevision" : 4
        }
        """

    private static let boardID096 = BoardID(rawValue: UUID(uuidString: "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01")!)

    private func temporaryRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MuralCloudManifest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func jsonObject(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// O `manifest.json` que está no disco, como objeto JSON.
    private func storedManifest(_ id: BoardID, in repository: BoardRepository) async throws -> [String: Any] {
        let url = await repository.packageURL(for: id).appendingPathComponent("manifest.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func writeStoredSchemaVersion(_ version: Int, of id: BoardID, in repository: BoardRepository) async throws {
        let url = await repository.packageURL(for: id).appendingPathComponent("manifest.json")
        var object = try await storedManifest(id, in: repository)
        object["schemaVersion"] = version
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    // MARK: Informação do iCloud

    @Test("Os nomes gravados no manifest não mudam: renomear um caso quebraria os murais já compartilhados")
    func storedNamesAreStable() throws {
        #expect(BoardCloudInfo.Database.private.rawValue == "private")
        #expect(BoardCloudInfo.Database.shared.rawValue == "shared")
        #expect(BoardCloudInfo.Permission.owner.rawValue == "owner")
        #expect(BoardCloudInfo.Permission.readWrite.rawValue == "readWrite")
        #expect(BoardCloudInfo.Permission.readOnly.rawValue == "readOnly")

        let stored = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(Self.receivedInfo))
        #expect(
            stored == [
                "database": "shared", "zoneName": "Mural-5B0F4C2E", "zoneOwnerName": "_d41d8cd98f00b204e9800998ecf8427e",
                "ownerDisplayName": "Ana", "permission": "readOnly",
            ])
        let own = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(Self.ownInfo))
        #expect(own["ownerDisplayName"] == nil, "o dono não tem nome para mostrar, e a chave fica de fora")
    }

    @Test("Só a permissão de ver é só leitura")
    func onlyReadOnlyPermissionIsReadOnly() {
        for permission in [BoardCloudInfo.Permission.owner, .readWrite] {
            var info = Self.ownInfo
            info.permission = permission
            #expect(!info.isReadOnly)
        }
        #expect(Self.receivedInfo.isReadOnly)
    }

    // MARK: Versão do manifest

    @Test("Manifest sem cloud é gravado com as mesmas chaves de antes, na versão 1")
    func manifestWithoutCloudKeepsTheOldShape() throws {
        let manifest = BoardManifest(id: BoardID(), name: "Casa", contentRevision: 3, workspaceRevision: 2)

        #expect(BoardManifest.currentSchemaVersion == 2)
        #expect(manifest.cloud == nil)
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.requiredSchemaVersion == 1)
        let object = try jsonObject(manifest)
        #expect(Set(object.keys) == Self.plainKeys)
        #expect(object["schemaVersion"] as? Int == 1)
    }

    @Test("Manifest com cloud exige a versão 2 e volta igual da ida e volta")
    func manifestWithCloudIsVersion2AndRoundTrips() throws {
        for info in [Self.receivedInfo, Self.ownInfo] {
            let manifest = BoardManifest(id: BoardID(), name: "Casa", contentRevision: 3, workspaceRevision: 2, cloud: info)
            #expect(manifest.schemaVersion == 2)
            #expect(manifest.requiredSchemaVersion == 2)

            let object = try jsonObject(manifest)
            #expect(Set(object.keys) == Self.plainKeys.union(["cloud"]))
            #expect(object["schemaVersion"] as? Int == 2)

            let decoded = try JSONDecoder().decode(BoardManifest.self, from: JSONEncoder().encode(manifest))
            #expect(decoded == manifest)
            #expect(decoded.cloud == info)
            #expect(decoded.schemaVersion == 2)
        }
    }

    @Test("Pôr o cloud sobe a versão para 2 e tirá-lo volta para 1")
    func settingAndClearingCloudMovesTheVersion() {
        var manifest = BoardManifest(id: BoardID())
        #expect(manifest.schemaVersion == 1)

        manifest.cloud = Self.receivedInfo
        #expect(manifest.schemaVersion == 2)

        manifest.cloud?.permission = .readWrite
        #expect(manifest.schemaVersion == 2, "mudar a permissão não tira o mural da versão 2")

        manifest.cloud = nil
        #expect(manifest.schemaVersion == 1)
    }

    @Test("Quem passa a versão ao montar o manifest continua sendo atendido")
    func explicitSchemaVersionIsKept() {
        #expect(BoardManifest(id: BoardID(), schemaVersion: 1).schemaVersion == 1)
        #expect(BoardManifest(id: BoardID(), schemaVersion: BoardManifest.currentSchemaVersion + 1).schemaVersion == 3)
        #expect(BoardManifest(id: BoardID(), cloud: Self.ownInfo, schemaVersion: 2).schemaVersion == 2)
    }

    @Test("Um manifest da 0.9.6, sem cloud, é lido como mural só deste Mac")
    func manifestFrom096IsRead() throws {
        let manifest = try JSONDecoder().decode(BoardManifest.self, from: Data(Self.manifestJSONFrom096.utf8))

        #expect(manifest.id == Self.boardID096)
        #expect(manifest.name == "Casa")
        #expect(manifest.schemaVersion == 1)
        #expect(manifest.contentRevision == 12 && manifest.workspaceRevision == 4)
        #expect(manifest.createdAt == Date(timeIntervalSinceReferenceDate: 779_000_000.25))
        #expect(manifest.updatedAt == Date(timeIntervalSinceReferenceDate: 780_000_000.5))
        #expect(manifest.cloud == nil)
    }

    // MARK: Repositório

    @Test("Ida e volta pelo repositório guarda o cloud e a versão 2, e o disco mostra a chave")
    func repositoryRoundTripKeepsCloud() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        let manifest = BoardManifest(id: id, name: "Casa", contentRevision: 1, cloud: Self.receivedInfo)
        let board = Board(items: [BoardItem(kind: .sticky, title: "Tinta", text: "Tinta azul")])

        try await repository.save(BoardRepositorySnapshot(manifest: manifest, board: board, workspace: .default))

        let loaded = try #require(await repository.load(id)).snapshot
        #expect(loaded.manifest.cloud == Self.receivedInfo)
        #expect(loaded.manifest.schemaVersion == 2)
        #expect(loaded.manifest.name == "Casa")
        #expect(loaded.board == board)
        let stored = try await storedManifest(id, in: repository)
        #expect(stored["schemaVersion"] as? Int == 2)
        let storedCloud = try #require(stored["cloud"] as? [String: String])
        #expect(storedCloud["zoneName"] == "Mural-5B0F4C2E" && storedCloud["permission"] == "readOnly")

        // Uma gravação seguinte, com revisão nova, leva o cloud junto.
        var next = loaded.manifest
        next.contentRevision += 1
        try await repository.save(BoardRepositorySnapshot(manifest: next, board: board, workspace: loaded.workspace))
        let reloaded = try #require(await repository.load(id)).snapshot.manifest
        #expect(reloaded.cloud == Self.receivedInfo && reloaded.schemaVersion == 2 && reloaded.contentRevision == 2)
    }

    @Test("Tirar o cloud e gravar de novo devolve o mural à versão 1, sem a chave")
    func clearingCloudWritesTheOldShapeAgain() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: BoardManifest(id: id, contentRevision: 1, cloud: Self.ownInfo), board: Board(), workspace: .default))

        var manifest = try #require(await repository.load(id)).snapshot.manifest
        manifest.cloud = nil
        manifest.contentRevision += 1
        try await repository.save(BoardRepositorySnapshot(manifest: manifest, board: Board(), workspace: .default))

        let stored = try await storedManifest(id, in: repository)
        #expect(Set(stored.keys) == Self.plainKeys)
        #expect(stored["schemaVersion"] as? Int == 1)
        #expect(try #require(await repository.load(id)).snapshot.manifest.cloud == nil)
    }

    @Test("Abrir e gravar um mural da 0.9.6 não muda o formato do manifest")
    func savingAManifestFrom096KeepsItsShape() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = Self.boardID096
        try await repository.save(id: id, board: Board(), workspace: .default)
        let manifestURL = await repository.packageURL(for: id).appendingPathComponent("manifest.json")
        try Data(Self.manifestJSONFrom096.utf8).write(to: manifestURL)

        let loaded = try #require(await repository.load(id)).snapshot
        #expect(loaded.manifest.cloud == nil && loaded.manifest.schemaVersion == 1)
        #expect(loaded.manifest.name == "Casa" && loaded.manifest.contentRevision == 12)

        var next = loaded.manifest
        next.contentRevision += 1
        try await repository.save(
            BoardRepositorySnapshot(
                manifest: next, board: Board(items: [BoardItem(kind: .sticky, title: "Tinta")]), workspace: loaded.workspace))

        let stored = try await storedManifest(id, in: repository)
        #expect(Set(stored.keys) == Self.plainKeys)
        #expect(stored["schemaVersion"] as? Int == 1)
        #expect(stored["contentRevision"] as? Int == 13)
    }

    // MARK: Biblioteca

    @Test("A listagem da biblioteca inclui o mural compartilhado, com o cloud, ao lado do que é só local")
    func libraryListsABoardWithCloud() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let sharedRoute = try await library.createNamedBoard("Compartilhado")
        _ = try await library.createNamedBoard("Local")

        let snapshot = try #require(await library.open(sharedRoute))
        var manifest = snapshot.manifest
        manifest.cloud = Self.receivedInfo
        manifest.contentRevision += 1
        try await library.repository(for: sharedRoute).save(
            BoardRepositorySnapshot(manifest: manifest, board: snapshot.board, workspace: snapshot.workspace))

        let report = try await library.listSavedReport()

        #expect(report.unreadable.isEmpty)
        #expect(report.entries.map(\.manifest.name) == ["Compartilhado", "Local"])
        let shared = try #require(report.entries.first)
        #expect(shared.route == sharedRoute)
        #expect(shared.manifest.cloud == Self.receivedInfo && shared.manifest.schemaVersion == 2)
        let local = try #require(report.entries.last)
        #expect(local.manifest.cloud == nil && local.manifest.schemaVersion == 1)
    }

    @Test("createBoard: nasce com o id e o cloud dados (manifest 2), e repetir o id devolve nil sem tocar em nada")
    func createBoardKeepsTheIDAndStoresTheCloud() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let id = BoardID()

        let route = try #require(try await library.createBoard(id: id, name: "Do iCloud", cloud: Self.receivedInfo))

        #expect(route == .saved(id))
        let created = try #require(await library.open(route))
        #expect(created.manifest.id == id && created.manifest.name == "Do iCloud")
        #expect(created.manifest.cloud == Self.receivedInfo && created.manifest.schemaVersion == 2)
        #expect(created.board.items.isEmpty)
        let stored = try await storedManifest(id, in: library.repository(for: route))
        #expect(stored["schemaVersion"] as? Int == 2)
        #expect(stored["cloud"] != nil)

        // Já existe um pacote com este id: nem o nome nem o cloud do que está no disco mudam.
        let again = try await library.createBoard(id: id, name: "Outro nome", cloud: Self.ownInfo)
        #expect(again == nil)
        #expect(try #require(await library.open(route)).manifest == created.manifest)

        // Sem cloud o mural é só deste Mac, como o de `createNamedBoard`.
        let localID = BoardID()
        let local = try #require(try await library.createBoard(id: localID, name: "Local", cloud: nil))
        let localManifest = try #require(await library.open(local)).manifest
        #expect(localManifest.cloud == nil && localManifest.schemaVersion == 1)
        let listed = try await library.listSavedReport().entries.map(\.manifest.id)
        #expect(Set(listed) == [id, localID])
    }

    @Test("Mudar só a permissão, sem revisão nova, é gravado")
    func permissionChangeWithoutRevisionIsSaved() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = BoardRepository(rootDirectory: root)
        let id = BoardID()
        var editable = Self.receivedInfo
        editable.permission = .readWrite
        let manifest = BoardManifest(id: id, contentRevision: 1, cloud: editable)
        try await repository.save(BoardRepositorySnapshot(manifest: manifest, board: Board(), workspace: .default))
        let loaded = try #require(await repository.load(id)).snapshot

        var downgraded = loaded.manifest
        downgraded.cloud?.permission = .readOnly
        try await repository.save(BoardRepositorySnapshot(manifest: downgraded, board: loaded.board, workspace: loaded.workspace))

        #expect(try #require(await repository.load(id)).snapshot.manifest.cloud?.permission == .readOnly)
    }

    @Test("Exportar e importar um mural compartilhado dá um pacote e um mural só locais")
    func exportAndImportDropTheCloud() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root, discardPackage: { try FileManager.default.removeItem(at: $0) })
        let route = try await library.createNamedBoard("Compartilhado")
        let snapshot = try #require(await library.open(route))
        var manifest = snapshot.manifest
        manifest.cloud = Self.ownInfo
        manifest.contentRevision += 1
        try await library.repository(for: route).save(
            BoardRepositorySnapshot(manifest: manifest, board: snapshot.board, workspace: snapshot.workspace))

        let exported = try await library.exportPackage(route)
        let stored = try #require(
            try JSONSerialization.jsonObject(with: Data(contentsOf: exported.appendingPathComponent("manifest.json")))
                as? [String: Any])
        #expect(Set(stored.keys) == Self.plainKeys)
        #expect(stored["schemaVersion"] as? Int == 1)

        let imported = try await library.importPackage(from: exported)
        let importedManifest = try #require(await library.open(imported)).manifest
        #expect(importedManifest.cloud == nil && importedManifest.schemaVersion == 1)
        #expect(try #require(await library.open(route)).manifest.cloud == Self.ownInfo)
    }

    // MARK: Versão futura

    @Test("Manifest de versão 3 é recusado ao abrir, ao listar e ao gravar por cima")
    func futureSchemaIsRefused() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = BoardLibrary(rootDirectory: root)
        let route = try await library.createNamedBoard("Do futuro")
        guard case .saved(let id) = route else {
            Issue.record("esperava uma rota de mural salvo, veio \(route)")
            return
        }
        let repository = try await library.repository(for: route)
        let snapshot = try #require(await library.open(route))
        var manifest = snapshot.manifest
        manifest.cloud = Self.receivedInfo
        manifest.contentRevision += 1
        try await repository.save(BoardRepositorySnapshot(manifest: manifest, board: snapshot.board, workspace: snapshot.workspace))

        // Montar o manifest numa versão que esta build não lê é recusado antes de qualquer arquivo mudar.
        var future = manifest
        future.contentRevision += 1
        future.schemaVersion = BoardManifest.currentSchemaVersion + 1
        await #expect(throws: BoardRepositoryError.futureManifestSchema(3)) {
            try await repository.save(BoardRepositorySnapshot(manifest: future, board: snapshot.board, workspace: snapshot.workspace))
        }
        #expect(try await repository.load(id)?.snapshot.manifest.schemaVersion == 2)

        // Um manifest já gravado na versão 3 (por uma build mais nova) não abre, não entra na lista e não é sobrescrito.
        try await writeStoredSchemaVersion(3, of: id, in: repository)
        await #expect(throws: BoardRepositoryError.futureManifestSchema(3)) { try await repository.load(id) }
        await #expect(throws: BoardRepositoryError.futureManifestSchema(3)) { try await library.open(route) }
        let report = try await library.listSavedReport()
        #expect(report.entries.isEmpty)
        #expect(report.unreadable.count == 1)
        var overwrite = manifest
        overwrite.contentRevision += 5
        await #expect(throws: BoardRepositoryError.futureManifestSchema(3)) {
            try await repository.save(BoardRepositorySnapshot(manifest: overwrite, board: snapshot.board, workspace: snapshot.workspace))
        }
        #expect(try await storedManifest(id, in: repository)["schemaVersion"] as? Int == 3)
    }
}
