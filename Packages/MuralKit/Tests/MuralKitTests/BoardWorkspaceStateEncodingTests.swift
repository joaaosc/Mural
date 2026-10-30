import Foundation
import StretchText
import Testing

@testable import MuralKit

@Suite("Gravação estável do estado de visualização")
struct BoardWorkspaceStateEncodingTests {
    private static let ids = (0..<12).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }

    private static func position(_ index: Int) -> ReadingPosition {
        .item(itemID: ids[index], visibleContentY: Double(index) * 10)
    }

    private static func memory(_ index: Int) -> OpenStretchMemory {
        OpenStretchMemory(source: "Texto \(index). Outra frase.", openIDs: [StretchID(path: [0])].compactMap { $0 })
    }

    private static func state(order: [Int]) -> BoardWorkspaceState {
        var positions: [UUID: ReadingPosition] = [:]
        var stretches: [UUID: OpenStretchMemory] = [:]
        for index in order {
            positions[ids[index]] = position(index)
            stretches[ids[index]] = memory(index)
        }
        return BoardWorkspaceState(readingPositions: positions, openStretches: stretches)
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    @Test("Estados iguais com ordem de inserção diferente geram os mesmos bytes")
    func sameBytesRegardlessOfInsertionOrder() throws {
        let forward = try Self.encoder().encode(Self.state(order: Array(0..<12)))
        for _ in 0..<5 {
            let shuffled = try Self.encoder().encode(Self.state(order: Array(0..<12).shuffled()))
            #expect(shuffled == forward)
        }
        // A lista plana sai ordenada pelo id.
        let object = try #require(try JSONSerialization.jsonObject(with: forward) as? [String: Any])
        let flat = try #require(object["readingPositions"] as? [Any])
        let keys = stride(from: 0, to: flat.count, by: 2).compactMap { flat[$0] as? String }
        #expect(keys == Self.ids.map(\.uuidString).sorted())
    }

    @Test("Mantém o formato de lista plana e lê o que o codificador padrão gravava")
    func staysReadableInTheOldFormat() throws {
        let state = Self.state(order: [3, 1, 2])
        let data = try Self.encoder().encode(state)
        #expect(try JSONDecoder().decode(BoardWorkspaceState.self, from: data) == state)

        // JSON montado à mão como o codificador padrão gravava: lista plana, em qualquer ordem.
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let reading = try #require(object["readingPositions"] as? [Any])
        let stretches = try #require(object["openStretches"] as? [Any])
        func reversedPairs(_ flat: [Any]) -> [Any] {
            stride(from: 0, to: flat.count, by: 2).reversed().flatMap { [flat[$0], flat[$0 + 1]] }
        }
        object["readingPositions"] = reversedPairs(reading)
        object["openStretches"] = reversedPairs(stretches)
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(BoardWorkspaceState.self, from: legacy) == state)

        // Estados gravados antes de `openStretches` existir.
        object["openStretches"] = nil
        let older = try JSONSerialization.data(withJSONObject: object)
        var expected = state
        expected.openStretches = [:]
        #expect(try JSONDecoder().decode(BoardWorkspaceState.self, from: older) == expected)
    }

    @Test("Dicionários vazios continuam como lista vazia")
    func emptyDictionaries() throws {
        let data = try Self.encoder().encode(BoardWorkspaceState())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((object["readingPositions"] as? [Any])?.isEmpty == true)
        #expect((object["openStretches"] as? [Any])?.isEmpty == true)
    }
}
