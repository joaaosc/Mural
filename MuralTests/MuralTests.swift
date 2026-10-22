import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
struct MuralTests {
    @Test("Testes de interface usam pasta própria, separada do mural real")
    func uiTestingUsesSeparateStore() {
        let real = LaunchConfiguration.store(arguments: [])
        let testing = LaunchConfiguration.store(arguments: ["-uiTestingKeep"])
        #expect(real.directory.lastPathComponent == "Mural")
        #expect(testing.directory.lastPathComponent == "MuralUITests")
        #expect(real.directory != testing.directory)
    }

    @Test("O modelo do aparelho fica desligado nos testes e quando pedido")
    func onDeviceModelSwitch() {
        #expect(LaunchConfiguration.usesOnDeviceModel(arguments: [], environment: [:]))
        #expect(!LaunchConfiguration.usesOnDeviceModel(arguments: ["-uiTesting"], environment: [:]))
        #expect(!LaunchConfiguration.usesOnDeviceModel(arguments: ["-disableOnDeviceModel"], environment: [:]))
        #expect(!LaunchConfiguration.usesOnDeviceModel(arguments: [], environment: ["XCTestConfigurationFilePath": "/x"]))
        #expect(!LaunchConfiguration.usesOnDeviceModel(), "esta execução é de teste")
    }

    @Test("Dentro da pasta também há filtro de pastas; num item, não há filtros")
    func filtersPerLevel() {
        #expect(Mural.BoardFilter.available(at: .board) == Mural.BoardFilter.allCases)
        #expect(Mural.BoardFilter.available(at: .folder).contains(.folders))
        #expect(Mural.BoardFilter.available(at: .item).isEmpty)
    }

    @Test("Nível da barra segue o topo da pilha")
    func levelFollowsPath() {
        let id = UUID()
        #expect(NavigationLevel(path: []) == .board)
        #expect(NavigationLevel(path: [.collection(id)]) == .folder)
        #expect(NavigationLevel(path: [.collection(id), .item(UUID())]) == .item)
    }

    @Test("Filtros da barra separam os tipos sem sobreposição")
    func filtersAreDisjoint() {
        for kind in ItemKind.allCases {
            let matches = Mural.BoardFilter.allCases.filter { $0.matches(kind) }
            #expect(matches.count <= 1, "\(kind) aparece em mais de um filtro")
        }
    }
}
