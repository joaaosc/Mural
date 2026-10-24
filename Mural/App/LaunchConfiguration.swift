import Foundation
import MuralKit

/// Onde o mural é gravado. Os testes de interface usam uma pasta própria.
enum LaunchConfiguration {
    static var isUITesting: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep")
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

    /// Raiz da biblioteca: a pasta padrão do app, a pasta dos testes de interface ou a da conferência
    /// manual (`-manualTesting`: prévias e páginas de verdade). Só calcula o endereço, sem criar nem apagar nada.
    ///
    /// A conferência manual tem pasta própria porque cada teste de interface apaga a sua ao abrir o app,
    /// mesmo com outra cópia do Mural aberta nela: as imagens dos murais dessa cópia sumiriam do disco.
    static func libraryRoot(arguments: [String] = ProcessInfo.processInfo.arguments) -> URL {
        let base = BoardStore.defaultDirectory()
        let folder: String
        if ["-uiTesting", "-uiTestingKeep"].contains(where: arguments.contains) {
            folder = "MuralUITests"
        } else if arguments.contains("-manualTesting") {
            folder = "MuralManualTests"
        } else {
            return base
        }
        return base.deletingLastPathComponent().appendingPathComponent(folder, isDirectory: true)
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

    /// De onde vem o iCloud: nos testes de interface, o iCloud falso, em memória; com o entitlement de CloudKit, o de verdade; no
    /// resto, nenhum. Sem o entitlement o app nem cria `CKContainer` (criá-lo encerra o app). O app aberto só para hospedar os
    /// testes unitários (`XCTestConfigurationFilePath`) fica sem sincronização: com o entitlement, ele tocaria a conta iCloud real
    /// de quem roda os testes. Os testes do controlador o criam por conta própria, com o iCloud falso.
    static func cloudSync(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hasCloudKitEntitlement: Bool = CloudAvailability.hasCloudKitEntitlement
    ) -> CloudSyncMode {
        if arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep") { return .inMemory }
        guard environment["XCTestConfigurationFilePath"] == nil else { return .off }
        return hasCloudKitEntitlement ? .cloudKit : .off
    }

    /// Se o detalhe de um link carrega a página de verdade: nos testes de interface, não; ele mostra uma página
    /// local de exemplo (`FixtureLinkPage`), sem rede.
    static func loadsLivePages(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        !(arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep"))
    }
}
