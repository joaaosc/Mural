import Foundation
import StretchText
import Testing

@testable import MuralKit

@Suite("Memória dos parágrafos abertos")
struct OpenStretchMemoryTests {
    static let body = "Primeira frase. Segunda frase.\n\nOutro bloco. Com duas frases."

    static func ids(_ paths: [Int]...) -> [StretchID] {
        paths.compactMap { StretchID(path: $0) }
    }

    @Test("Guarda os IDs em ordem e vale só para o mesmo texto")
    func matchesSource() {
        let memory = OpenStretchMemory(source: Self.body, openIDs: Self.ids([1], [0]))
        #expect(memory.openIDs == Self.ids([0], [1]))
        #expect(memory.matches(Self.body))
        #expect(!memory.matches(Self.body + " Mais."))
    }

    @Test("Estado salvo antes da memória existir abre com ela vazia")
    func decodesOldWorkspace() throws {
        let state = BoardWorkspaceState(readingPositions: [UUID(): .item(itemID: UUID(), visibleContentY: 3)])
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        json.removeValue(forKey: "openStretches")
        let decoded = try JSONDecoder().decode(BoardWorkspaceState.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.openStretches.isEmpty)
        #expect(decoded.readingPositions == state.readingPositions)
    }

    @Test("Ida e volta pelo JSON")
    func roundTrip() throws {
        let state = BoardWorkspaceState(openStretches: [UUID(): OpenStretchMemory(source: Self.body, openIDs: Self.ids([1]))])
        #expect(try JSONDecoder().decode(BoardWorkspaceState.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test("Validação mantém a memória válida e tira a de item apagado, texto mudado, post-it ou vazia")
    func validation() {
        let note = BoardItem(kind: .text, title: "N", text: Self.body)
        let edited = BoardItem(kind: .text, title: "E", text: Self.body + " Editado.")
        let sticky = BoardItem(kind: .sticky, title: "S", text: Self.body)
        let empty = BoardItem(kind: .text, title: "V", text: Self.body)
        let missing = UUID()
        let board = Board(items: [note, edited, sticky, empty])
        let open = OpenStretchMemory(source: Self.body, openIDs: Self.ids([0]))
        let state = BoardWorkspaceState(openStretches: [
            note.id: open, edited.id: open, sticky.id: open, missing: open,
            empty.id: OpenStretchMemory(source: Self.body, openIDs: []),
        ])
        let result = state.canonicalized(for: board)
        #expect(result.state.openStretches == [note.id: open])
        let expected = [edited.id, sticky.id, missing, empty.id].map(WorkspaceValidationIssue.removedOpenStretches)
        #expect(result.issues.count == expected.count)
        for issue in expected {
            #expect(result.issues.contains(issue))
        }
    }
}
