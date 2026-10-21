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
}
