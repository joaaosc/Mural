import Foundation
import MuralKit

/// Onde o mural é gravado. Os testes e os perfis manuais usam pastas próprias.
enum LaunchConfiguration {
    static var isUITesting: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep")
    }

    /// Perfil manual determinístico do canvas; só vale junto de `-manualTesting`.
    static func usesPerformanceFixture(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-manualTesting") && arguments.contains("-performanceFixture")
    }

    /// `-uiTesting`: começa do mural de exemplo, apagando a pasta dos testes de interface (só ela).
    /// `-uiTestingKeep`: reabre a pasta de testes sem apagar (teste de persistência).
    static func store(arguments: [String] = ProcessInfo.processInfo.arguments) -> BoardStore {
        let root = libraryRoot(arguments: arguments)
        if arguments.contains("-uiTesting") {
            try? FileManager.default.removeItem(at: root)
        }
        return BoardStore(directory: root)
    }

    /// Raiz da biblioteca: a pasta padrão do app, a pasta dos testes de interface, a da conferência
    /// manual (`-manualTesting`) ou a pasta dedicada do perfil estrutural. Só calcula o endereço,
    /// sem criar nem apagar nada.
    ///
    /// A conferência manual tem pasta própria porque cada teste de interface apaga a sua ao abrir o app,
    /// mesmo com outra cópia do Mural aberta nela: as imagens dos murais dessa cópia sumiriam do disco.
    static func libraryRoot(arguments: [String] = ProcessInfo.processInfo.arguments) -> URL {
        let base = BoardStore.defaultDirectory()
        let folder: String
        if usesPerformanceFixture(arguments: arguments) {
            folder = "MuralPerformanceTests"
        } else if ["-uiTesting", "-uiTestingKeep"].contains(where: arguments.contains) {
            folder = "MuralUITests"
        } else if arguments.contains("-manualTesting") {
            folder = "MuralManualTests"
        } else {
            return base
        }
        return base.deletingLastPathComponent().appendingPathComponent(folder, isDirectory: true)
    }

    /// Recria somente a pasta dedicada do perfil, sem tocar na biblioteca real ou na pasta dos testes de UI.
    /// O argumento exige `-manualTesting` para não virar uma operação destrutiva acidental em uma execução comum.
    static func preparePerformanceFixtureIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        guard usesPerformanceFixture(arguments: arguments) else { return }
        let root = libraryRoot(arguments: arguments)
        do {
            if FileManager.default.fileExists(atPath: root.path) {
                try FileManager.default.removeItem(at: root)
            }
            try BoardStore(directory: root).save(
                PerformanceBoardFixture.make(size: .items2000, mediaDensity: .percent50))
        } catch {
            preconditionFailure("Não foi possível preparar a fixture de performance: \(error)")
        }
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

    /// Quem baixa as capas de música: nos testes de interface, um buscador falso, sem rede; no resto, o de verdade.
    static func musicArtworkFetcher(arguments: [String] = ProcessInfo.processInfo.arguments) -> any MusicArtworkFetching {
        if arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep") { return FixtureMusicArtworkFetcher() }
        return SystemMusicArtworkFetcher()
    }

    /// Se o detalhe de um link carrega a página de verdade: nos testes de interface, não; ele mostra uma página
    /// local de exemplo (`FixtureLinkPage`), sem rede.
    static func loadsLivePages(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        !(arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep"))
    }
}
