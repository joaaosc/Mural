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

    @Test("Dentro da pasta não há filtro de pastas; num item, não há filtros")
    func filtersPerLevel() {
        #expect(BoardFilter.available(at: .board) == BoardFilter.allCases)
        #expect(!BoardFilter.available(at: .folder).contains(.folders))
        #expect(BoardFilter.available(at: .item).isEmpty)
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
            let matches = BoardFilter.allCases.filter { $0.matches(kind) }
            #expect(matches.count <= 1, "\(kind) aparece em mais de um filtro")
        }
    }
}
