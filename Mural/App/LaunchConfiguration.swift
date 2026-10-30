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

    /// As pastas das cópias de "Editar antes de colar". `inside` fica dentro da biblioteca (`<raiz>/PasteEdits`), no contêiner
    /// do app, onde o Texto edita no lugar. `visible` é a pasta Downloads de verdade (`~/Downloads/Edições do Mural`), onde a
    /// Pré-Visualização edita no lugar. Nos testes de interface (`-uiTesting`, `-uiTestingKeep`) ela fica dentro da biblioteca de
    /// testes (`<raiz>/PasteEditsVisible`), para nenhum teste tocar o Downloads de quem os roda; `-realPasteEditor` volta à pasta
    /// de verdade, para a conferência com a Pré-Visualização. Só calcula os endereços, sem criar nada.
    static func pasteEditRoots(arguments: [String] = ProcessInfo.processInfo.arguments) -> PasteEditFiles.Roots {
        let library = libraryRoot(arguments: arguments)
        let isUITesting = ["-uiTesting", "-uiTestingKeep"].contains(where: arguments.contains)
        let visible =
            isUITesting && !arguments.contains("-realPasteEditor")
            ? library.appendingPathComponent("PasteEditsVisible", isDirectory: true)
            : realHomeDirectory().appendingPathComponent("Downloads", isDirectory: true)
                .appendingPathComponent("Edições do Mural", isDirectory: true)
        return PasteEditFiles.Roots(
            inside: library.appendingPathComponent("PasteEdits", isDirectory: true), visible: visible)
    }

    /// A pasta pessoal de verdade (`/Users/<nome>`). No App Sandbox, a Downloads que o `FileManager` devolve é um link dentro
    /// do contêiner, e a Pré-Visualização precisa receber o caminho real. Usa o banco de usuários do sistema e, sem ele, a
    /// pasta pessoal do `FileManager`.
    nonisolated static func realHomeDirectory() -> URL {
        if let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Pasta das imagens e dos ícones de prévia dos links de um mural: `<raiz>/LinkPreviews/<uuid do mural>`.
    static func linkPreviewsDirectory(
        for boardID: BoardID, arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL {
        linkPreviewsDirectoryProvider(arguments: arguments)(boardID)
    }

    /// O mesmo endereço como função que não depende do ator principal, para a biblioteca chamar de onde roda (a raiz é fixada agora).
    static func linkPreviewsDirectoryProvider(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> @Sendable (BoardID) -> URL {
        let root = libraryRoot(arguments: arguments).appendingPathComponent("LinkPreviews", isDirectory: true)
        return { root.appendingPathComponent($0.rawValue.uuidString, isDirectory: true) }
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
    /// de quem roda os testes. Os testes do controlador o criam por conta própria, com o iCloud falso. O perfil de desempenho
    /// (`-performanceFixture`) também fica sem: as medições não incluem o iCloud, e o mural de exemplo não vai para a conta.
    static func cloudSync(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hasCloudKitEntitlement: Bool = CloudAvailability.hasCloudKitEntitlement
    ) -> CloudSyncMode {
        if arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep") { return .inMemory }
        guard environment["XCTestConfigurationFilePath"] == nil else { return .off }
        guard !usesPerformanceFixture(arguments: arguments) else { return .off }
        return hasCloudKitEntitlement ? .cloudKit : .off
    }

    /// Se o app guarda as cópias dos murais na pasta Mural do iCloud Drive: só com o entitlement do iCloud Drive e fora dos testes de
    /// interface, do perfil manual e de desempenho e do app que hospeda os testes unitários, que não devem tocar o iCloud Drive de
    /// quem os roda. Os testes do controlador o criam por conta própria, com uma pasta temporária.
    static func mirrorsToICloudDrive(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hasCloudDocumentsEntitlement: Bool = CloudAvailability.hasCloudDocumentsEntitlement
    ) -> Bool {
        let testArguments = ["-uiTesting", "-uiTestingKeep", "-manualTesting", "-performanceFixture"]
        guard !arguments.contains(where: testArguments.contains) else { return false }
        guard environment["XCTestConfigurationFilePath"] == nil else { return false }
        return hasCloudDocumentsEntitlement
    }

    #if DEBUG
    /// A demonstração do Live Share, para conferir a interface sem chamada do FaceTime: `-liveShareDemo`, e só junto de `-uiTesting`
    /// ou `-uiTestingKeep`, porque ela depende do iCloud falso. Só existe nas compilações de desenvolvimento.
    static func isLiveShareDemo(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-liveShareDemo") && (arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep"))
    }
    #endif

    /// Se o detalhe de um link carrega a página de verdade: nos testes de interface, não; ele mostra uma página
    /// local de exemplo (`FixtureLinkPage`), sem rede.
    static func loadsLivePages(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        !(arguments.contains("-uiTesting") || arguments.contains("-uiTestingKeep"))
    }
}
