import Foundation
import MuralKit
import Testing

@testable import Mural

/// Só caminhos: nenhum destes testes cria ou apaga pastas (`-uiTesting` apagaria a pasta de testes).
@MainActor
struct LaunchConfigurationTests {
    @Test("A raiz da biblioteca é a pasta padrão e, nos testes de interface, uma pasta própria ao lado dela")
    func libraryRootFollowsLaunchArguments() {
        let real = LaunchConfiguration.libraryRoot(arguments: [])

        #expect(real.path == BoardStore.defaultDirectory().path)
        for argument in ["-uiTesting", "-uiTestingKeep"] {
            let testing = LaunchConfiguration.libraryRoot(arguments: ["-quiet", argument])
            #expect(testing.lastPathComponent == "MuralUITests")
            #expect(testing.deletingLastPathComponent().path == real.deletingLastPathComponent().path)
        }
    }

    @Test("O mural continua sendo gravado na raiz da biblioteca")
    func storeUsesTheLibraryRoot() {
        #expect(LaunchConfiguration.store(arguments: []).directory.path == LaunchConfiguration.libraryRoot(arguments: []).path)
        #expect(
            LaunchConfiguration.store(arguments: ["-uiTestingKeep"]).directory.path
                == LaunchConfiguration.libraryRoot(arguments: ["-uiTestingKeep"]).path)
    }

    @Test("As prévias de link de cada mural ficam em LinkPreviews/<uuid do mural>, dentro da raiz")
    func linkPreviewsDirectoryIsPerBoardInsideTheRoot() {
        let first = BoardID()
        let second = BoardID()

        for arguments in [[], ["-uiTestingKeep"]] {
            let root = LaunchConfiguration.libraryRoot(arguments: arguments)
            let directory = LaunchConfiguration.linkPreviewsDirectory(for: first, arguments: arguments)

            #expect(directory.path == root.path + "/LinkPreviews/" + first.rawValue.uuidString)
            #expect(directory.path != LaunchConfiguration.linkPreviewsDirectory(for: second, arguments: arguments).path)
        }
    }

    @Test("Os testes de interface usam o buscador de prévias falso, sem rede; o resto usa o do sistema")
    func linkPreviewFetcherFollowsLaunchArguments() {
        #expect(LaunchConfiguration.linkPreviewFetcher(arguments: []) is SystemLinkPreviewFetcher)
        #expect(LaunchConfiguration.linkPreviewFetcher(arguments: ["-quiet"]) is SystemLinkPreviewFetcher)
        for argument in ["-uiTesting", "-uiTestingKeep"] {
            #expect(LaunchConfiguration.linkPreviewFetcher(arguments: ["-quiet", argument]) is FixtureLinkPreviewFetcher)
        }
    }

    @Test("A conferência manual usa pasta própria, que os testes de interface não apagam, com prévias e páginas de verdade")
    func manualTestingUsesOwnLibraryWithRealPreviews() {
        let arguments = ["-manualTesting"]
        let manual = LaunchConfiguration.libraryRoot(arguments: arguments)
        let wipedByUITests = LaunchConfiguration.libraryRoot(arguments: ["-uiTesting"])

        #expect(manual.lastPathComponent == "MuralManualTests")
        #expect(manual.deletingLastPathComponent().path == BoardStore.defaultDirectory().deletingLastPathComponent().path)
        #expect(manual.path != wipedByUITests.path)
        #expect(manual.path != BoardStore.defaultDirectory().path)
        #expect(LaunchConfiguration.linkPreviewFetcher(arguments: arguments) is SystemLinkPreviewFetcher)
        #expect(LaunchConfiguration.loadsLivePages(arguments: arguments))
    }
}
