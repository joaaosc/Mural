import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
struct MuralTests {
    @Test("Lista copiada como texto volta igual ao ser colada")
    func checklistCopyRoundTrip() {
        var original = SampleBoard.thingsINeed
        let firstEntry = original.sections[0].entries[0].id
        original.toggle(entryID: firstEntry)

        let text = ItemDetailView.plainText(of: original)
        #expect(ContentClassifier.kind(forText: text) == .checklist)

        let parsed = ChecklistDocument.parse(text)
        #expect(parsed.title == original.title)
        #expect(parsed.sections.map(\.title) == original.sections.map(\.title))
        #expect(parsed.progress == original.progress)
    }

    @Test("Testes de interface usam pasta própria, separada do mural real")
    func uiTestingUsesSeparateStore() {
        let real = LaunchConfiguration.store(arguments: [])
        let testing = LaunchConfiguration.store(arguments: ["-uiTestingKeep"])
        #expect(real.directory.lastPathComponent == "Mural")
        #expect(testing.directory.lastPathComponent == "MuralUITests")
        #expect(real.directory != testing.directory)
    }

    @Test("Filtros da barra separam os tipos sem sobreposição")
    func filtersAreDisjoint() {
        for kind in ItemKind.allCases {
            let matches = BoardFilter.allCases.filter { $0.matches(kind) }
            #expect(matches.count <= 1, "\(kind) aparece em mais de um filtro")
        }
    }
}
