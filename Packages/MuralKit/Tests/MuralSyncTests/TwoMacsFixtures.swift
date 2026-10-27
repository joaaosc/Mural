import Foundation
import MuralSync
import Synchronization
import Testing

@testable import MuralKit

/// Falha de um teste de dois Macs: as rodadas não pararam de mudar alguma coisa.
struct EchoError: Error, CustomStringConvertible {
    var rounds: Int
    var description: String { "eco: iCloud, murais ou pendências ainda mudavam depois de \(rounds) rodadas" }
}

/// Um Mac de teste: o host em memória, a loja em disco, o coordenador e o motor falso, numa pasta temporária própria.
struct TestMac {
    let user: String
    let root: URL
    let host: SyncTestHost
    let store: SyncMetadataStore
    let coordinator: BoardSyncCoordinator
    let engine: InMemorySyncEngine
    let boardID: BoardID

    var items: URL { root.appendingPathComponent("Items", isDirectory: true) }

    var board: Board {
        get async { await host.board(boardID) }
    }

    var name: String {
        get async { await host.name(boardID) }
    }

    /// - Parameter hasLocalBoard: `false` deixa o Mac sem o pacote do mural, como um Mac que ainda não o recebeu: o host o cria em
    ///   `Items/` quando o coordenador adota a zona.
    static func make(
        user: String, scope: CloudDatabaseScope, cloud: InMemoryCloud, boardID: BoardID, name: String, board: Board = Board(),
        files: [String] = [], hasLocalBoard: Bool = true
    ) async throws -> TestMac {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralTwoMacs-\(UUID().uuidString)", isDirectory: true)
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        for file in files { try Data("conteúdo de \(file)".utf8).write(to: items.appendingPathComponent(file)) }
        let host = SyncTestHost(adoptedItemsDirectory: items)
        if hasLocalBoard { await host.add(boardID, name: name, board: board, itemsDirectory: items) }
        let store = SyncMetadataStore(directory: root.appendingPathComponent("Sync", isDirectory: true))
        let coordinator = BoardSyncCoordinator(scope: scope, store: store, host: host)
        let engine = InMemorySyncEngine(user: user, scope: scope, cloud: cloud, coordinator: coordinator)
        return TestMac(user: user, root: root, host: host, store: store, coordinator: coordinator, engine: engine, boardID: boardID)
    }

    /// Uma edição local: o app grava o mural e entrega ao motor o que o coordenador diz estar pendente.
    func edit(_ change: (inout Board) -> Void) async throws {
        var board = await host.board(boardID)
        change(&board)
        await host.write(board, for: boardID)
        await engine.add(try await coordinator.pendingChanges(for: boardID))
    }

    func rename(_ name: String) async throws {
        await host.rename(name, for: boardID)
        await engine.add(try await coordinator.pendingChanges(for: boardID))
    }

    /// Um arquivo de mídia em `Items/`, antes de algum cartão citá-lo.
    func writeFile(_ name: String, contents: String) throws {
        try Data(contents.utf8).write(to: items.appendingPathComponent(name))
    }

    func fileContents(_ name: String) -> String? {
        (try? Data(contentsOf: items.appendingPathComponent(name))).flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Os convites que um motor falso entregou, uma lista por entrega, na ordem em que vieram. O fecho do motor é `@Sendable`, então o
/// registro tem trava.
final class ShareLog: Sendable {
    private let batches = Mutex<[[ShareSummary]]>([])

    func record(_ shares: [ShareSummary]) {
        batches.withLock { $0.append(shares) }
    }

    var all: [[ShareSummary]] { batches.withLock { $0 } }
}

/// O dono e um convidado no mesmo mural, cada um com o seu coordenador e o seu motor falso, sobre um só iCloud falso.
struct TwoMacs {
    static let ownerUser = "ana"
    static let guestUser = "bia"

    let cloud: InMemoryCloud
    let boardID: BoardID
    let owner: TestMac
    let guest: TestMac

    var zoneName: String { CloudSchema.zoneName(for: boardID) }
    /// A zona como o dono a vê.
    var ownerZone: CloudZoneID { CloudZoneID(name: zoneName) }
    /// A zona como o convidado a vê.
    var guestZone: CloudZoneID { CloudZoneID(name: zoneName, ownerName: Self.ownerUser) }

    /// O dono já tem o mural (com a zona criada e tudo pendente) e o convidado já foi convidado e acompanha um mural vazio de mesmo
    /// nome, como o app faz ao aceitar o convite. Nada foi enviado nem buscado ainda.
    /// - Parameters:
    ///   - guestPermission: o que o iCloud falso dá ao convidado.
    ///   - guestTracksAs: a permissão que o coordenador do convidado conhece; diferente da anterior é uma permissão desatualizada.
    ///   - guestSendsInitialPending: se o motor do convidado recebe as pendências que `startTracking` devolveu (o registro do mural,
    ///     com o mural ainda vazio). Sem elas o convidado só recebe, até a primeira edição.
    ///   - guestAdopts: o Mac do convidado não tem o pacote do mural nem o acompanha, só foi convidado: o motor dele adota a zona
    ///     na primeira busca. `guestTracksAs` e `guestSendsInitialPending` não valem.
    static func make(
        board: Board = Board(), name: String = "Casa", files: [String] = [],
        guestPermission: InMemoryCloud.GuestPermission = .readWrite,
        guestTracksAs: BoardCloudInfo.Permission = .readWrite,
        guestSendsInitialPending: Bool = true,
        guestAdopts: Bool = false
    ) async throws -> TwoMacs {
        let cloud = InMemoryCloud()
        let boardID = BoardID()
        let zoneName = CloudSchema.zoneName(for: boardID)

        let owner = try await TestMac.make(
            user: ownerUser, scope: .private, cloud: cloud, boardID: boardID, name: name, board: board, files: files)
        try await owner.engine.startZone(for: boardID)
        let ownerInfo = BoardCloudInfo(
            database: .private, zoneName: zoneName, zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner)
        await owner.engine.add(try await owner.coordinator.startTracking(boardID, cloud: ownerInfo))

        try await cloud.share(zone: zoneName, owner: ownerUser, with: guestUser, permission: guestPermission)
        let guest = try await TestMac.make(
            user: guestUser, scope: .shared, cloud: cloud, boardID: boardID, name: name, hasLocalBoard: !guestAdopts)
        if !guestAdopts {
            let guestInfo = BoardCloudInfo(
                database: .shared, zoneName: zoneName, zoneOwnerName: ownerUser, ownerDisplayName: "Ana", permission: guestTracksAs)
            let guestPending = try await guest.coordinator.startTracking(boardID, cloud: guestInfo)
            if guestSendsInitialPending { await guest.engine.add(guestPending) }
        }
        return TwoMacs(cloud: cloud, boardID: boardID, owner: owner, guest: guest)
    }

    /// Um segundo Mac do dono: o mesmo usuário e o mesmo banco privado, sem o pacote do mural e sem acompanhá-lo. O motor dele adota
    /// a zona na primeira busca. Quem chama apaga `root`.
    func makeSecondOwnerMac() async throws -> TestMac {
        try await TestMac.make(
            user: Self.ownerUser, scope: .private, cloud: cloud, boardID: boardID, name: "", hasLocalBoard: false)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: owner.root)
        try? FileManager.default.removeItem(at: guest.root)
    }

    /// Os registros da zona no iCloud falso, com as marcas de alteração.
    func cloudRecords() async -> [CloudRecord] {
        await cloud.records(inZone: zoneName, owner: Self.ownerUser)
    }

    func cloudRecord(_ name: String) async -> CloudRecord? {
        await cloudRecords().first { $0.id.name == name }
    }

    // MARK: Sincronizar

    private struct Snapshot: Equatable {
        var cloud: [CloudRecord]
        var ownerBoard: Board
        var ownerName: String
        var guestBoard: Board
        var guestName: String
        var ownerPending: Set<PendingChange>
        var guestPending: Set<PendingChange>
        var extraBoard: Board?
        var extraName: String?
        var extraPending: Set<PendingChange>?
    }

    private func snapshot(including extra: TestMac? = nil) async -> Snapshot {
        Snapshot(
            cloud: await cloudRecords(), ownerBoard: await owner.board, ownerName: await owner.name, guestBoard: await guest.board,
            guestName: await guest.name, ownerPending: await owner.engine.pending, guestPending: await guest.engine.pending,
            extraBoard: await extra?.board, extraName: await extra?.name, extraPending: await extra?.engine.pending)
    }

    /// Uma rodada: os dois enviam e depois os dois buscam.
    func round() async throws {
        try await owner.engine.sendChanges()
        try await guest.engine.sendChanges()
        try await owner.engine.fetchChanges()
        try await guest.engine.fetchChanges()
    }

    /// Repete rodadas até uma delas não mudar nada (iCloud, murais e pendências).
    /// - Returns: quantas rodadas, contando a última, que não mudou nada.
    /// - Throws: `EchoError` se passa do limite: algo se repete sem fim.
    @discardableResult
    func settle(maximumRounds: Int = 10) async throws -> Int {
        for number in 1...maximumRounds {
            let before = await snapshot()
            try await round()
            if await snapshot() == before { return number }
        }
        throw EchoError(rounds: maximumRounds)
    }

    /// Como `settle()`, com um Mac a mais (o segundo Mac do dono, `makeSecondOwnerMac()`): os três enviam e depois os três buscam.
    @discardableResult
    func settle(including extra: TestMac, maximumRounds: Int = 10) async throws -> Int {
        for number in 1...maximumRounds {
            let before = await snapshot(including: extra)
            try await owner.engine.sendChanges()
            try await guest.engine.sendChanges()
            try await extra.engine.sendChanges()
            try await owner.engine.fetchChanges()
            try await guest.engine.fetchChanges()
            try await extra.engine.fetchChanges()
            if await snapshot(including: extra) == before { return number }
        }
        throw EchoError(rounds: maximumRounds)
    }

    // MARK: Conferir

    /// Os arquivos de mídia do iCloud que nenhum cartão cita.
    func orphanMediaFiles() async -> [String] {
        let records = await cloudRecords()
        var cited = Set<String>()
        for record in records where record.type == CloudSchema.RecordType.card.rawValue {
            if case .card(let item, _)? = try? CardRecordMapping.card(from: record) { cited.formUnion(item.assetFileNames) }
        }
        return records.filter { $0.type == CloudSchema.RecordType.mediaFile.rawValue && !cited.contains($0.id.name) }
            .map(\.id.name).sorted()
    }

    /// Os dois murais iguais (cartões na projeção `SharedFieldPolicy.shared` e na ordem da lista, textos livres e nome), nada pendente,
    /// nenhum arquivo órfão no iCloud e a estrutura válida nos dois.
    func expectConverged(expectingNoIssues: Bool = true, sourceLocation: SourceLocation = #_sourceLocation) async {
        let ownerBoard = await owner.board
        let guestBoard = await guest.board
        #expect(
            ownerBoard.items.map(SharedFieldPolicy.shared) == guestBoard.items.map(SharedFieldPolicy.shared),
            "os cartões ou a ordem da lista diferem entre os dois Macs", sourceLocation: sourceLocation)
        #expect(Set(ownerBoard.freeTexts) == Set(guestBoard.freeTexts), "os textos livres diferem", sourceLocation: sourceLocation)
        #expect(ownerBoard.freeTexts.count == guestBoard.freeTexts.count, sourceLocation: sourceLocation)
        #expect(await owner.name == (await guest.name), "o nome do mural difere", sourceLocation: sourceLocation)
        #expect(await owner.engine.pending.isEmpty, "sobrou pendência no dono", sourceLocation: sourceLocation)
        #expect(await guest.engine.pending.isEmpty, "sobrou pendência no convidado", sourceLocation: sourceLocation)
        #expect(await orphanMediaFiles().isEmpty, "sobrou arquivo órfão no iCloud", sourceLocation: sourceLocation)
        await expectCloudMatches(ownerBoard, sourceLocation: sourceLocation)
        Self.expectValidStructure(ownerBoard, owner: "dono", sourceLocation: sourceLocation)
        Self.expectValidStructure(guestBoard, owner: "convidado", sourceLocation: sourceLocation)
        if expectingNoIssues {
            #expect(await owner.coordinator.issues().isEmpty, "o dono tem aviso", sourceLocation: sourceLocation)
            #expect(await guest.coordinator.issues().isEmpty, "o convidado tem aviso", sourceLocation: sourceLocation)
        }
    }

    /// O que o iCloud guarda é o que os murais têm: os mesmos cartões, com a ordem da lista nos números de empilhamento, e os mesmos
    /// textos livres. Registros que esta build não entende (app mais novo) ficam de fora da conta.
    private func expectCloudMatches(_ board: Board, sourceLocation: SourceLocation) async {
        var cards: [(item: BoardItem, layer: Double)] = []
        var freeTexts: [BoardFreeText] = []
        for record in await cloudRecords() {
            switch CloudSchema.RecordType(rawValue: record.type) {
            case .card?:
                if case .card(let item, let layer?)? = try? CardRecordMapping.card(from: record) { cards.append((item, layer)) }
            case .freeText?:
                if case .freeText(let freeText)? = try? CardRecordMapping.freeText(from: record) { freeTexts.append(freeText) }
            case .mural?, .mediaFile?, nil:
                break
            }
        }
        #expect(
            Set(cards.map(\.item)) == Set(board.items.map(SharedFieldPolicy.shared)) && cards.count == board.items.count,
            "os cartões do iCloud diferem dos do mural", sourceLocation: sourceLocation)
        #expect(
            cards.sorted { $0.layer < $1.layer }.map(\.item.id) == board.items.map(\.id),
            "a ordem de empilhamento do iCloud difere da lista", sourceLocation: sourceLocation)
        #expect(
            Set(freeTexts) == Set(board.freeTexts) && freeTexts.count == board.freeTexts.count,
            "os textos livres do iCloud diferem dos do mural", sourceLocation: sourceLocation)
    }

    /// Ids únicos e cadeia de pastas válida em cada cartão.
    static func expectValidStructure(_ board: Board, owner: String, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(
            Set(board.items.map(\.id)).count == board.items.count, "ids de cartão repetidos no \(owner)", sourceLocation: sourceLocation)
        #expect(
            Set(board.freeTexts.map(\.id)).count == board.freeTexts.count, "ids de texto livre repetidos no \(owner)",
            sourceLocation: sourceLocation)
        let byID = Dictionary(board.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for item in board.items {
            #expect(
                Board.hasValidParentChain(item, in: byID), "cadeia de pastas inválida no \(owner): \(item.title)",
                sourceLocation: sourceLocation)
        }
    }
}

/// Gerador pseudoaleatório com semente fixa (SplitMix64): a mesma semente dá sempre a mesma sequência.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    /// Um inteiro em `0..<bound`.
    mutating func int(below bound: Int) -> Int {
        Int(next() % UInt64(bound))
    }

    /// Um UUID válido tirado do gerador, para os ids dos cartões serem os mesmos a cada execução.
    mutating func uuid() -> UUID {
        func hex(_ value: UInt64) -> String {
            let digits = String(value, radix: 16, uppercase: true)
            return String(repeating: "0", count: 16 - digits.count) + digits
        }
        let high = hex(next())
        let low = hex(next())
        let text =
            "\(high.prefix(8))-\(high.dropFirst(8).prefix(4))-4\(high.suffix(3))-8\(low.prefix(3))-\(low.suffix(12))"
        return UUID(uuidString: text) ?? UUID()
    }
}
