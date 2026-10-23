import Foundation
import MuralKit
import MuralSync
import Testing

@Suite("iCloud: nomes do esquema e registro neutro")
struct CloudSchemaTests {
    private static let boardUUID = "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01"

    // MARK: Zona

    @Test("O nome da zona é \"mural-\" mais o UUID do mural e volta ao mesmo mural")
    func zoneNameRoundTrips() throws {
        let fixed = BoardID(rawValue: try #require(UUID(uuidString: Self.boardUUID)))
        #expect(CloudSchema.zoneName(for: fixed) == "mural-\(Self.boardUUID)")
        #expect(CloudSchema.boardID(fromZoneName: "mural-\(Self.boardUUID)") == fixed)

        for _ in 0..<50 {
            let id = BoardID()
            #expect(CloudSchema.boardID(fromZoneName: CloudSchema.zoneName(for: id)) == id)
        }
    }

    @Test("Nome de zona fora do padrão não é de mural")
    func foreignZoneNamesAreNotBoards() {
        let names = [
            "",
            "mural",
            "mural-",
            "mural-abc",
            "mural-\(Self.boardUUID)-2",
            "Mural-\(Self.boardUUID)",
            "mural_\(Self.boardUUID)",
            "outro-\(Self.boardUUID)",
            " mural-\(Self.boardUUID)",
            "mural-\(Self.boardUUID) ",
            "mural-\(Self.boardUUID.lowercased())",
            "mural-5B0F4C2E8C0B4B1F9D753E1A7F2A9C01",
            Self.boardUUID,
            "_defaultZone",
        ]
        for name in names {
            #expect(CloudSchema.boardID(fromZoneName: name) == nil, "\(name)")
        }
    }

    // MARK: Nomes fixos

    @Test("Os nomes de tipos, do registro do mural e das chaves não mudam: renomear quebraria os murais já sincronizados")
    func storedNamesAreStable() {
        #expect(CloudSchema.RecordType.allCases.map(\.rawValue) == ["Mural", "Card", "FreeText", "MediaFile"])
        #expect(CloudSchema.muralRecordName == "mural")
        #expect(
            Set(CloudSchema.Key.allCases.map(\.rawValue)) == [
                "kind", "title", "createdAt", "parentID", "x", "y", "layer", "folderX", "folderY", "fileName", "text", "caption",
                "stickyColor", "colorTag", "tag", "checklist", "imageMetadata", "link", "reminder", "music", "attachments",
                "formatVersion", "name", "file", "cardID",
            ])
    }

    // MARK: Registro

    @Test("O registro novo não tem campos, criador nem campos de sistema; a zona própria usa o dono padrão")
    func newRecordIsEmpty() {
        let zone = CloudZoneID(name: CloudSchema.zoneName(for: BoardID()))
        #expect(zone.ownerName == "__defaultOwner__")
        #expect(zone.ownerName == CloudZoneID.defaultOwnerName)

        let record = CloudRecord(
            id: CloudRecordID(zone: zone, name: CloudSchema.muralRecordName), type: CloudSchema.RecordType.mural.rawValue)
        #expect(record.fields.isEmpty)
        #expect(record.creatorUserRecordName == nil)
        #expect(record.systemFields == nil)
    }

    @Test("Os campos de sistema e o criador contam na igualdade do registro, e cada tipo de valor é distinto")
    func serverDataCountsForEquality() {
        let id = CloudRecordID(zone: CloudZoneID(name: "mural-x", ownerName: "_dono"), name: "mural")
        let plain = CloudRecord(id: id, type: "Mural", fields: ["name": .string("Casa")])

        var stamped = plain
        stamped.systemFields = Data([1, 2, 3])
        var authored = plain
        authored.creatorUserRecordName = "_criador"

        #expect(plain == plain)
        #expect(stamped != plain)
        #expect(authored != plain)
        #expect(Set([plain, stamped, authored, plain]).count == 3)
        #expect(CloudValue.int(1) != CloudValue.double(1))
        #expect(CloudValue.string("a") != CloudValue.data(Data("a".utf8)))
    }

    @Test("Zona e registro são identificadores que a gravação em JSON devolve iguais")
    func identifiersAreCodable() throws {
        let id = CloudRecordID(zone: CloudZoneID(name: "mural-x", ownerName: "_dono"), name: "mural")
        let decoded = try JSONDecoder().decode(CloudRecordID.self, from: JSONEncoder().encode(id))
        #expect(decoded == id)
    }
}
