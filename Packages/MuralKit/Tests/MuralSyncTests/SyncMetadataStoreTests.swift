import Foundation
import MuralKit
import MuralSync
import Testing

@Suite("iCloud: o que este Mac sabe de cada mural")
struct SyncMetadataStoreTests {
    /// Uma pasta que ainda não existe, dentro de outra que também não: a loja cria o que precisar.
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralSyncStore-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Mural/Sync", isDirectory: true)
    }

    private func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent().deletingLastPathComponent())
    }

    private func stateFile(_ id: BoardID, in directory: URL) -> URL {
        directory.appendingPathComponent("boards/\(id.rawValue.uuidString).json")
    }

    // MARK: Ida e volta

    @Test("Um estado completo, com cartões de todos os tipos, volta igual do disco, também por outra instância")
    func completeStateRoundTrips() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let id = BoardID()
        let state = SyncFixtures.syncState()
        #expect(Set(state.base.items.map(\.kind)) == Set(ItemKind.allCases), "o exemplo precisa ter um cartão de cada tipo")
        let store = SyncMetadataStore(directory: directory)

        try await store.save(state, for: id)

        #expect(try await store.state(for: id) == state)
        let reopened = SyncMetadataStore(directory: directory)
        let loaded = try #require(try await reopened.state(for: id))
        #expect(loaded == state)
        #expect(loaded.base.freeTexts == state.base.freeTexts)
        #expect(loaded.layers == state.layers && loaded.systemFields == state.systemFields)
        #expect(loaded.baseName == "Casa 🏠" && loaded.cloud == SyncFixtures.cloudInfo)
        #expect(loaded.baseBoardFormatVersion == 10 && loaded.mediaOwners == state.mediaOwners && loaded.mediaOwners.count == 2)
        let dates = { (board: Board) in board.items.map { $0.createdAt.timeIntervalSinceReferenceDate.bitPattern } }
        #expect(dates(loaded.base) == dates(state.base), "as datas voltam bit a bit")
    }

    @Test("Antes do primeiro envio o estado não tem nome nem nada enviado, e a chave do nome fica de fora")
    func minimalStateRoundTrips() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let id = BoardID()
        let state = BoardSyncState(cloud: SyncFixtures.cloudInfo)
        let store = SyncMetadataStore(directory: directory)

        try await store.save(state, for: id)

        let loaded = try #require(try await store.state(for: id))
        #expect(loaded == state)
        #expect(loaded.baseName == nil && loaded.base == Board() && loaded.layers.isEmpty)
        #expect(loaded.baseBoardFormatVersion == nil && loaded.mediaOwners.isEmpty)
        #expect(loaded.systemFields.isEmpty && loaded.uploadedFiles.isEmpty && loaded.unsupportedRecordNames.isEmpty)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile(id, in: directory))) as? [String: Any])
        #expect(object["baseName"] == nil && object["baseBoardFormatVersion"] == nil)
    }

    @Test("Gravar de novo troca o estado, e cada mural guarda o seu")
    func saveReplacesAndBoardsAreIndependent() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let first = BoardID()
        let second = BoardID()
        var state = SyncFixtures.syncState()
        try await store.save(state, for: first)
        try await store.save(BoardSyncState(cloud: SyncFixtures.cloudInfo, baseName: "Outro"), for: second)

        state.baseName = "Casa nova"
        state.uploadedFiles.insert("AAAAAAAA-0000-4000-8000-000000000003.mov")
        state.unsupportedRecordNames.removeAll()
        try await store.save(state, for: first)

        #expect(try await store.state(for: first) == state)
        #expect(try await store.state(for: second)?.baseName == "Outro")
    }

    @Test("O mesmo estado dá sempre os mesmos bytes, qualquer que seja a ordem em que foi montado")
    func sameStateGivesSameBytes() async throws {
        let ids = (0..<200).map { _ in UUID() }
        func state(reversed: Bool) -> BoardSyncState {
            var layers: [UUID: Double] = [:]
            var systemFields: [String: Data] = [:]
            var uploaded = Set<String>()
            var owners: [String: UUID] = [:]
            var unsupported = Set<String>()
            for index in reversed ? Array(ids.indices.reversed()) : Array(ids.indices) {
                let name = ids[index].uuidString
                layers[ids[index]] = Double(index)
                systemFields[name] = Data([UInt8(index % 256)])
                uploaded.insert("\(name).jpg")
                owners["\(name).jpg"] = ids[index]
                unsupported.insert(name)
            }
            return BoardSyncState(
                cloud: SyncFixtures.cloudInfo, baseBoardFormatVersion: 3, layers: layers, systemFields: systemFields,
                uploadedFiles: uploaded,
                mediaOwners: owners, unsupportedRecordNames: unsupported)
        }
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let forward = BoardID()
        let backward = BoardID()

        try await store.save(state(reversed: false), for: forward)
        try await store.save(state(reversed: true), for: backward)

        let forwardBytes = try Data(contentsOf: stateFile(forward, in: directory))
        #expect(forwardBytes == (try Data(contentsOf: stateFile(backward, in: directory))))
        #expect(try await store.state(for: forward) == state(reversed: true))
    }

    @Test("Um estado gravado antes da versão do mural e dos donos dos arquivos continua abrindo, com nil e vazio")
    func stateWrittenBeforeTheNewFieldsStillOpens() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let id = BoardID()
        let owner = UUID()
        let state = BoardSyncState(
            cloud: SyncFixtures.cloudInfo, baseName: "Casa", baseBoardFormatVersion: 3, layers: [owner: 0.5],
            uploadedFiles: ["foto.jpg"], mediaOwners: ["foto.jpg": owner])
        let store = SyncMetadataStore(directory: directory)
        try await store.save(state, for: id)
        // Como o arquivo era antes: sem os dois campos.
        let url = stateFile(id, in: directory)
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["baseBoardFormatVersion"] != nil && object["mediaOwners"] != nil)
        object["baseBoardFormatVersion"] = nil
        object["mediaOwners"] = nil
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let loaded = try #require(try await store.state(for: id))

        #expect(loaded.baseBoardFormatVersion == nil && loaded.mediaOwners.isEmpty)
        var expected = state
        expected.baseBoardFormatVersion = nil
        expected.mediaOwners = [:]
        #expect(loaded == expected, "o resto do estado abre como estava")
    }

    @Test("Dono de arquivo que não é UUID é arquivo ilegível")
    func badMediaOwnerIsCorrupted() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let id = BoardID()
        try await store.save(SyncFixtures.syncState(), for: id)
        let url = stateFile(id, in: directory)
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["mediaOwners"] = ["foto.jpg": "não é UUID"]
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        await #expect(throws: SyncMetadataStoreError.self) { try await store.state(for: id) }
    }

    // MARK: Onde fica no disco

    @Test("O estado fica em boards/<UUID>.json, o do motor em engine-<banco>.data, e a gravação não deixa sobras")
    func filesLayout() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let id = BoardID()
        let state = SyncFixtures.syncState()

        try await store.save(state, for: id)
        try await store.saveEngineState(Data([1, 2, 3]), for: .private)
        try await store.saveEngineState(Data([4, 5]), for: .shared)

        #expect(CloudDatabaseScope.private.rawValue == "private" && CloudDatabaseScope.shared.rawValue == "shared")
        let fileManager = FileManager.default
        #expect(
            try fileManager.contentsOfDirectory(atPath: directory.appendingPathComponent("boards").path) == [
                "\(id.rawValue.uuidString).json"
            ])
        #expect(
            Set(try fileManager.contentsOfDirectory(atPath: directory.path)) == ["boards", "engine-private.data", "engine-shared.data"])
        #expect(try Data(contentsOf: directory.appendingPathComponent("engine-private.data")) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: directory.appendingPathComponent("engine-shared.data")) == Data([4, 5]))

        // O JSON é legível: as camadas ficam por UUID e os conjuntos em lista ordenada.
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile(id, in: directory))) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "cloud", "base", "baseName", "baseBoardFormatVersion", "layers", "systemFields", "uploadedFiles", "mediaOwners",
                "unsupportedRecordNames",
            ])
        #expect(object["baseBoardFormatVersion"] as? Int == 10)
        let owners = try #require(object["mediaOwners"] as? [String: String])
        #expect(owners == state.mediaOwners.mapValues(\.uuidString))
        let layers = try #require(object["layers"] as? [String: Double])
        #expect(layers == Dictionary(uniqueKeysWithValues: state.layers.map { ($0.key.uuidString, $0.value) }))
        #expect(object["uploadedFiles"] as? [String] == state.uploadedFiles.sorted())
        #expect(object["unsupportedRecordNames"] as? [String] == state.unsupportedRecordNames.sorted())
    }

    // MARK: Ausente, remover e listar

    @Test("Sem nada gravado, o estado é nil, a lista é vazia e ler não cria pasta")
    func missingStateIsNil() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)

        #expect(try await store.state(for: BoardID()) == nil)
        #expect(try await store.boardIDs().isEmpty)
        #expect(try await store.engineState(for: .private) == nil)
        #expect(try await store.engineState(for: .shared) == nil)
        try await store.remove(BoardID())
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Remover esquece só aquele mural, e remover o que não existe não é erro")
    func removeForgetsOnlyThatBoard() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let removed = BoardID()
        let kept = BoardID()
        let state = SyncFixtures.syncState()
        try await store.save(state, for: removed)
        try await store.save(state, for: kept)
        try await store.saveEngineState(Data([9]), for: .private)

        try await store.remove(removed)
        try await store.remove(removed)

        #expect(try await store.state(for: removed) == nil)
        #expect(try await store.state(for: kept) == state)
        #expect(try await store.boardIDs() == [kept])
        #expect(try await store.engineState(for: .private) == Data([9]), "o estado do motor não é de nenhum mural")
        #expect(!FileManager.default.fileExists(atPath: stateFile(removed, in: directory).path))
    }

    @Test("A lista de murais ignora o que não é <UUID>.json")
    func listingIgnoresGarbage() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let first = BoardID()
        let second = BoardID()
        try await store.save(SyncFixtures.syncState(), for: first)
        try await store.save(SyncFixtures.syncState(), for: second)

        let boards = directory.appendingPathComponent("boards", isDirectory: true)
        let stray = "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01"
        let junk = [
            ".DS_Store", "notas.txt", "nao-e-uuid.json", "abcdef12-3456-4789-abcd-ef1234567890.json", "\(stray).JSON",
            "\(stray).json.tmp", stray, "\(stray)-2.json", ".\(stray).json",
        ]
        for name in junk {
            try Data("lixo".utf8).write(to: boards.appendingPathComponent(name))
        }
        // Uma pasta com nome de arquivo de estado também não conta.
        try FileManager.default.createDirectory(
            at: boards.appendingPathComponent("\(UUID().uuidString).json", isDirectory: true), withIntermediateDirectories: true)

        let ids = try await store.boardIDs()

        #expect(Set(ids) == [first, second])
        #expect(ids.count == 2)
        #expect(ids.map { $0.rawValue.uuidString } == ids.map { $0.rawValue.uuidString }.sorted(), "a ordem é fixa")
    }

    // MARK: Estado do motor

    @Test("O estado do motor é um por banco, e gravar de novo troca o anterior")
    func engineStateIsPerScope() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let privateState = Data("privado".utf8)
        let sharedState = Data([0x00, 0xFF, 0x10, 0x80])

        try await store.saveEngineState(privateState, for: .private)
        #expect(try await store.engineState(for: .private) == privateState)
        #expect(try await store.engineState(for: .shared) == nil)

        try await store.saveEngineState(sharedState, for: .shared)
        #expect(try await store.engineState(for: .shared) == sharedState)
        #expect(try await store.engineState(for: .private) == privateState)

        try await store.saveEngineState(Data(), for: .private)
        #expect(try await store.engineState(for: .private) == Data(), "estado vazio é um estado, não ausência")
        let reopened = SyncMetadataStore(directory: directory)
        #expect(try await reopened.engineState(for: .shared) == sharedState)
    }

    // MARK: Zonas recusadas

    @Test("As zonas recusadas são uma lista por banco, em ordem fixa no disco, e voltam iguais também por outra instância")
    func declinedZonesRoundTripPerScope() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let ownZone = CloudZoneID(name: "mural-5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01")
        let guestZoneB = CloudZoneID(name: "mural-AAAAAAAA-0000-4000-8000-000000000002", ownerName: "_b")
        let guestZoneA = CloudZoneID(name: "mural-AAAAAAAA-0000-4000-8000-000000000001", ownerName: "_b")
        #expect(try await store.declinedZones(for: .private).isEmpty, "sem arquivo, nada foi recusado")
        #expect(!FileManager.default.fileExists(atPath: directory.path), "ler não cria pasta")

        try await store.saveDeclinedZones([ownZone], for: .private)
        try await store.saveDeclinedZones([guestZoneB, guestZoneA], for: .shared)

        let reopened = SyncMetadataStore(directory: directory)
        #expect(try await reopened.declinedZones(for: .private) == [ownZone])
        #expect(try await reopened.declinedZones(for: .shared) == [guestZoneA, guestZoneB])
        let data = try Data(contentsOf: directory.appendingPathComponent("declined-shared.json"))
        let list = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(
            list == [
                ["name": guestZoneA.name, "ownerName": "_b"], ["name": guestZoneB.name, "ownerName": "_b"],
            ], "lista ordenada por dono e nome")
        let files = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(files == ["declined-private.json", "declined-shared.json"], "a gravação atômica não deixa sobras")

        // Gravar de novo troca a lista, e a vazia é uma lista (não some o arquivo, nem sobra o que foi tirado).
        try await store.saveDeclinedZones([], for: .shared)
        #expect(try await store.declinedZones(for: .shared).isEmpty)
        #expect(try await store.declinedZones(for: .private) == [ownZone], "o outro banco não muda")
    }

    @Test("O mesmo conjunto de zonas recusadas dá sempre os mesmos bytes, qualquer que seja a ordem em que foi montado")
    func declinedZonesGiveSameBytes() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let zones = (0..<50).map { CloudZoneID(name: "mural-\(UUID().uuidString)", ownerName: "_dono\($0 % 3)") }

        try await store.saveDeclinedZones(Set(zones), for: .private)
        try await store.saveDeclinedZones(Set(zones.reversed()), for: .shared)

        let privateBytes = try Data(contentsOf: directory.appendingPathComponent("declined-private.json"))
        let sharedBytes = try Data(contentsOf: directory.appendingPathComponent("declined-shared.json"))
        #expect(privateBytes == sharedBytes)
        #expect(try await store.declinedZones(for: .private) == Set(zones))
    }

    @Test("Arquivo de zonas recusadas ilegível dá erro próprio e continua no disco, intacto; gravar por cima conserta")
    func corruptedDeclinedFileIsAnError() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let zone = CloudZoneID(name: "mural-5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01")
        try await store.saveDeclinedZones([zone], for: .private)
        let url = directory.appendingPathComponent("declined-private.json")

        for bytes in [Data("{ isto não é JSON".utf8), Data(), Data("{}".utf8), Data(#"[{"name":"x"}]"#.utf8)] {
            try bytes.write(to: url)

            let error = try await #require(throws: SyncMetadataStoreError.self) { try await store.declinedZones(for: .private) }

            guard case .corrupted(let message) = error else {
                Issue.record("esperava corrupted, veio \(error)")
                continue
            }
            #expect(message.contains("declined-private.json"))
            #expect(try Data(contentsOf: url) == bytes, "o arquivo ilegível continua como estava")
        }
        #expect(try await store.declinedZones(for: .shared).isEmpty, "o outro banco não é afetado")

        try await store.saveDeclinedZones([zone], for: .private)
        #expect(try await store.declinedZones(for: .private) == [zone])
    }

    // MARK: Espera pela primeira busca

    @Test("A espera pela primeira busca só vai ao disco quando ligada, e o estado gravado sem ela abre desligado")
    func awaitingFirstFetchIsStoredOnlyWhenSet() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let plain = BoardID()
        let waiting = BoardID()
        let both = BoardID()
        try await store.save(BoardSyncState(cloud: SyncFixtures.cloudInfo), for: plain)
        try await store.save(BoardSyncState(cloud: SyncFixtures.cloudInfo, isAwaitingFirstFetch: true), for: waiting)
        try await store.save(BoardSyncState(cloud: SyncFixtures.cloudInfo, needsFullFetch: true, isAwaitingFirstFetch: true), for: both)

        func object(_ id: BoardID) throws -> [String: Any] {
            try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile(id, in: directory))) as? [String: Any])
        }
        #expect(try object(plain)["isAwaitingFirstFetch"] == nil && object(plain)["needsFullFetch"] == nil)
        #expect(try object(waiting)["isAwaitingFirstFetch"] as? Bool == true && object(waiting)["needsFullFetch"] == nil)
        #expect(try object(both)["isAwaitingFirstFetch"] as? Bool == true && object(both)["needsFullFetch"] as? Bool == true)

        let reopened = SyncMetadataStore(directory: directory)
        let loadedPlain = try #require(try await reopened.state(for: plain))
        #expect(!loadedPlain.isAwaitingFirstFetch && !loadedPlain.needsFullFetch)
        let loadedWaiting = try #require(try await reopened.state(for: waiting))
        #expect(loadedWaiting.isAwaitingFirstFetch && !loadedWaiting.needsFullFetch)
        let loadedBoth = try #require(try await reopened.state(for: both))
        #expect(loadedBoth.isAwaitingFirstFetch && loadedBoth.needsFullFetch)
        #expect(loadedWaiting == BoardSyncState(cloud: SyncFixtures.cloudInfo, isAwaitingFirstFetch: true))
    }

    // MARK: Arquivo ilegível

    @Test("Arquivo ilegível dá erro próprio e continua no disco, intacto")
    func corruptedFileIsAnErrorAndStays() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let id = BoardID()
        let good = SyncFixtures.syncState()
        try await store.save(good, for: id)
        let url = stateFile(id, in: directory)

        let garbage = [Data("{ isto não é JSON".utf8), Data(), Data([0xFF, 0xFE, 0x00]), Data("{}".utf8), Data("[]".utf8)]
        for bytes in garbage {
            try bytes.write(to: url)

            let error = try await #require(throws: SyncMetadataStoreError.self) { try await store.state(for: id) }

            guard case .corrupted(let message) = error else {
                Issue.record("esperava corrupted, veio \(error)")
                continue
            }
            #expect(message.contains(url.lastPathComponent))
            #expect(try Data(contentsOf: url) == bytes, "o arquivo ilegível continua como estava")
            #expect(try await store.boardIDs() == [id], "o mural segue na lista: quem chama decide o que fazer")
        }

        // Quem chama pode refazer o estado: gravar por cima conserta, e remover limpa.
        try await store.save(good, for: id)
        #expect(try await store.state(for: id) == good)
        try Data("{".utf8).write(to: url)
        try await store.remove(id)
        #expect(try await store.state(for: id) == nil)
    }

    @Test("Chave de camada que não é UUID, ou repetida em outra caixa, é arquivo ilegível e não derruba o app")
    func badLayerKeysAreCorrupted() async throws {
        let directory = temporaryDirectory()
        defer { cleanUp(directory) }
        let store = SyncMetadataStore(directory: directory)
        let id = BoardID()
        try await store.save(SyncFixtures.syncState(), for: id)
        let url = stateFile(id, in: directory)
        let original = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let uuid = "ABCDEF12-3456-4789-ABCD-EF1234567890"

        let badLayers: [[String: Double]] = [["não é UUID": 1], [uuid: 1, uuid.lowercased(): 2]]
        for layers in badLayers {
            var object = original
            object["layers"] = layers
            let bytes = try JSONSerialization.data(withJSONObject: object)
            try bytes.write(to: url)

            await #expect(throws: SyncMetadataStoreError.self) { try await store.state(for: id) }
            #expect(try Data(contentsOf: url) == bytes)
        }
    }
}
