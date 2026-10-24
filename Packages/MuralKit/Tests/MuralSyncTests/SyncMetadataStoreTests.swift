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
        #expect(loaded.systemFields.isEmpty && loaded.uploadedFiles.isEmpty && loaded.unsupportedRecordNames.isEmpty)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile(id, in: directory))) as? [String: Any])
        #expect(object["baseName"] == nil)
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
            var unsupported = Set<String>()
            for index in reversed ? Array(ids.indices.reversed()) : Array(ids.indices) {
                let name = ids[index].uuidString
                layers[ids[index]] = Double(index)
                systemFields[name] = Data([UInt8(index % 256)])
                uploaded.insert("\(name).jpg")
                unsupported.insert(name)
            }
            return BoardSyncState(
                cloud: SyncFixtures.cloudInfo, layers: layers, systemFields: systemFields, uploadedFiles: uploaded,
                unsupportedRecordNames: unsupported)
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
        #expect(try fileManager.contentsOfDirectory(atPath: directory.appendingPathComponent("boards").path) == ["\(id.rawValue.uuidString).json"])
        #expect(Set(try fileManager.contentsOfDirectory(atPath: directory.path)) == ["boards", "engine-private.data", "engine-shared.data"])
        #expect(try Data(contentsOf: directory.appendingPathComponent("engine-private.data")) == Data([1, 2, 3]))
        #expect(try Data(contentsOf: directory.appendingPathComponent("engine-shared.data")) == Data([4, 5]))

        // O JSON é legível: as camadas ficam por UUID e os conjuntos em lista ordenada.
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: stateFile(id, in: directory))) as? [String: Any])
        #expect(
            Set(object.keys) == ["cloud", "base", "baseName", "layers", "systemFields", "uploadedFiles", "unsupportedRecordNames"])
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
