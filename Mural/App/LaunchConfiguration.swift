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
        let root = libraryRoot(arguments: arguments)
        if arguments.contains("-uiTesting") {
            try? FileManager.default.removeItem(at: root)
        }
        return BoardStore(directory: root)
    }

    /// Raiz da biblioteca: a pasta padrão do app ou, nos testes de interface, a pasta de testes.
    /// Só calcula o endereço, sem criar nem apagar nada.
    static func libraryRoot(arguments: [String] = ProcessInfo.processInfo.arguments) -> URL {
        let base = BoardStore.defaultDirectory()
        guard arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep") else { return base }
        return base.deletingLastPathComponent().appendingPathComponent("MuralUITests", isDirectory: true)
    }

    /// Pasta das imagens e dos ícones de prévia dos links de um mural: `<raiz>/LinkPreviews/<uuid do mural>`.
    static func linkPreviewsDirectory(
        for boardID: BoardID, arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL {
        libraryRoot(arguments: arguments)
            .appendingPathComponent("LinkPreviews", isDirectory: true)
            .appendingPathComponent(boardID.rawValue.uuidString, isDirectory: true)
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

    /// Quem busca as prévias dos links: nos testes de interface, um buscador falso, sem rede; no resto, o de verdade.
    static func linkPreviewFetcher(arguments: [String] = ProcessInfo.processInfo.arguments) -> any LinkPreviewFetching {
        if arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep") { return FixtureLinkPreviewFetcher() }
        return SystemLinkPreviewFetcher()
    }
}
