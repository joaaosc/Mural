import Foundation
import MuralKit

/// Onde o mural é gravado. Os testes de interface usam uma pasta própria.
enum LaunchConfiguration {
    static var isUITesting: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep")
    }

    /// `-uiTesting`: começa do mural de exemplo, apagando a pasta de testes.
    /// `-uiTestingKeep`: reabre a pasta de testes sem apagar (teste de persistência).
    static func store(arguments: [String] = ProcessInfo.processInfo.arguments) -> BoardStore {
        let base = BoardStore.defaultDirectory()
        guard arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep") else {
            return BoardStore(directory: base)
        }
        let testDirectory = base.deletingLastPathComponent().appendingPathComponent("MuralUITests", isDirectory: true)
        if arguments.contains("-uiTesting") {
            try? FileManager.default.removeItem(at: testDirectory)
        }
        return BoardStore(directory: testDirectory)
    }

    /// O modelo do aparelho escolhe as frases curtas, menos nos testes: lá a frase
    /// precisa ser a primeira, sem mudar sozinha no meio de uma verificação.
    /// `-disableOnDeviceModel` desliga também numa execução comum.
    static func usesOnDeviceModel(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let testArguments = ["-uiTesting", "-uiTestingKeep", "-disableOnDeviceModel"]
        guard !arguments.contains(where: testArguments.contains) else { return false }
        return environment["XCTestConfigurationFilePath"] == nil
    }
}
