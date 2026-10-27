import Foundation
import Testing

@testable import Mural

/// O ambiente do iCloud desta cópia do app e a pasta do estado de sincronização que cada ambiente usa.
@Suite("Ambiente do iCloud e pasta do estado de sincronização")
struct SyncLocationTests {
    // MARK: Ambiente

    /// Os valores dos dois entitlements e o ambiente que eles dizem.
    struct EnvironmentCase: Sendable {
        var container: String?
        var aps: String?
        var expected: CloudEnvironment
    }

    @Test(
        "O ambiente vem da chave do container; sem ela, do aps-environment; sem nenhuma, é o de desenvolvimento",
        arguments: [
            EnvironmentCase(container: "Production", aps: "development", expected: .production),
            EnvironmentCase(container: "Development", aps: "production", expected: .development),
            EnvironmentCase(container: nil, aps: "production", expected: .production),
            EnvironmentCase(container: nil, aps: "development", expected: .development),
            EnvironmentCase(container: nil, aps: nil, expected: .development),
            EnvironmentCase(container: "Staging", aps: "production", expected: .production),
        ])
    func environmentFollowsTheEntitlements(_ item: EnvironmentCase) {
        let environment = CloudAvailability.environment(containerEnvironment: item.container, apsEnvironment: item.aps)

        #expect(environment == item.expected)
    }

    @Test("Um valor que não é texto não conta como ambiente")
    func nonTextEntitlementValuesAreIgnored() {
        #expect(CloudAvailability.environment(containerEnvironment: 1, apsEnvironment: "production") == .production)
        #expect(CloudAvailability.environment(containerEnvironment: ["Production"], apsEnvironment: nil) == .development)
        _ = CloudAvailability.currentEnvironment  // a leitura do processo não pode encerrar o app
    }

    // MARK: Pasta

    /// Uma raiz de biblioteca temporária; `create` a cria vazia, e sem ela a raiz nem existe (a primeira execução do app).
    private static func makeRoot(create: Bool = true) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralSyncLocation-\(UUID().uuidString)", isDirectory: true)
        if create { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        return root
    }

    private static func marker(in root: URL) -> URL {
        root.appendingPathComponent(SyncLocation.markerFileName, isDirectory: false)
    }

    private static func writeMarker(_ text: String, in root: URL) throws {
        try Data(text.utf8).write(to: marker(in: root))
    }

    private static func readMarker(in root: URL) throws -> String {
        String(decoding: try Data(contentsOf: marker(in: root)), as: UTF8.self)
    }

    @Test("Sem marca: grava a marca com o ambiente atual e devolve Sync, com o estado que já existia")
    func withoutMarkerClaimsSyncAndKeepsItsContent() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let state = root.appendingPathComponent("Sync/boards/estado.json", isDirectory: false)
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("estado antigo".utf8).write(to: state)

        let location = try SyncLocation.resolve(root: root, environment: .development)

        #expect(location.directory == root.appendingPathComponent("Sync", isDirectory: true))
        #expect(!location.isOtherEnvironment)
        #expect(try Self.readMarker(in: root) == "Development")
        #expect(try String(contentsOf: state, encoding: .utf8) == "estado antigo", "o estado que já existia continua lá")
    }

    @Test("Primeira execução, sem nem a raiz: cria a raiz e a marca")
    func firstRunCreatesTheRootAndTheMarker() throws {
        let root = try Self.makeRoot(create: false)
        defer { try? FileManager.default.removeItem(at: root) }

        let location = try SyncLocation.resolve(root: root, environment: .production)

        #expect(location.directory == root.appendingPathComponent("Sync", isDirectory: true))
        #expect(!location.isOtherEnvironment)
        #expect(try Self.readMarker(in: root) == "Production")
    }

    @Test("Mesmo ambiente da marca: Sync, sem mudar a marca", arguments: ["Production", "Production\n"])
    func sameEnvironmentUsesSync(markerText: String) throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMarker(markerText, in: root)

        let location = try SyncLocation.resolve(root: root, environment: .production)

        #expect(location.directory == root.appendingPathComponent("Sync", isDirectory: true))
        #expect(!location.isOtherEnvironment)
        #expect(try Self.readMarker(in: root) == markerText)
    }

    @Test(
        "Outro ambiente: pasta própria, Sync-<Ambiente>, sem tocar em Sync nem na marca",
        arguments: zip([CloudEnvironment.development, .production], [CloudEnvironment.production, .development]))
    func otherEnvironmentUsesItsOwnFolder(owner: CloudEnvironment, current: CloudEnvironment) throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMarker(owner.rawValue, in: root)
        let state = root.appendingPathComponent("Sync/engine-private.data", isDirectory: false)
        try FileManager.default.createDirectory(at: state.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("do dono".utf8).write(to: state)

        let location = try SyncLocation.resolve(root: root, environment: current)

        #expect(location.directory == root.appendingPathComponent("Sync-\(current.rawValue)", isDirectory: true))
        #expect(location.isOtherEnvironment)
        #expect(try Self.readMarker(in: root) == owner.rawValue, "a marca continua com o dono de Sync")
        #expect(try String(contentsOf: state, encoding: .utf8) == "do dono")
    }

    @Test("Marca vazia ou só com espaços vale como ausente", arguments: ["", "\n", "  \n"])
    func emptyMarkerIsTreatedAsMissing(markerText: String) throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMarker(markerText, in: root)

        let location = try SyncLocation.resolve(root: root, environment: .production)

        #expect(location.directory == root.appendingPathComponent("Sync", isDirectory: true))
        #expect(!location.isOtherEnvironment)
        #expect(try Self.readMarker(in: root) == "Production")
    }

    @Test("Marca com texto desconhecido lança e fica como está", arguments: ["Staging", "production", "Development e Production"])
    func unrecognizedMarkerThrows(markerText: String) throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writeMarker(markerText, in: root)

        #expect(throws: SyncLocation.MarkerError.unrecognized(markerText)) {
            try SyncLocation.resolve(root: root, environment: .production)
        }
        #expect(try Self.readMarker(in: root) == markerText, "não se adivinha: a marca não é regravada")
    }

    @Test("Marca com bytes que não são texto também lança")
    func binaryMarkerThrows() throws {
        let root = try Self.makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([0xFF, 0xFE, 0xFD]).write(to: Self.marker(in: root))

        #expect(throws: SyncLocation.MarkerError.self) {
            try SyncLocation.resolve(root: root, environment: .production)
        }
    }
}
