import CloudKit
import Foundation
import MuralKit
import Testing

@testable import MuralSync

/// O mural de exemplo que prepara o esquema do iCloud (`CloudSchemaSample`), sem rede e sem container: só os registros e a conversão
/// para `CKRecord`. A gravação de verdade no CloudKit não tem teste automático.
@Suite("Exemplo do esquema do iCloud")
struct CloudSchemaSampleTests {
    private static let zone = CloudZoneID(name: "esquema-5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01")
    private static let mediaFile = URL(fileURLWithPath: "/tmp/exemplo/AAAAAAAA-0000-4000-8000-000000000003.jpg")

    private func sample() throws -> [CloudRecord] {
        try CloudSchemaSample.records(in: Self.zone, mediaFile: Self.mediaFile)
    }

    private func records(_ type: CloudSchema.RecordType, in records: [CloudRecord]) -> [CloudRecord] {
        records.filter { $0.type == type.rawValue }
    }

    /// Os cartões do exemplo lidos de volta, falhando o teste se algum não for suportado.
    private func decodedCards(_ records: [CloudRecord]) throws -> [(item: BoardItem, layer: Double?, record: CloudRecord)] {
        try self.records(.card, in: records).compactMap { record in
            let decoding = try CardRecordMapping.card(from: record)
            guard case .card(let item, let layer) = decoding else {
                Issue.record("o cartão \(record.id.name) veio como \(decoding)")
                return nil
            }
            return (item, layer, record)
        }
    }

    // MARK: Tipos e chaves

    @Test("Os quatro tipos de registro aparecem: um mural, vários cartões, um texto livre e um arquivo de mídia")
    func everyRecordTypeAppears() throws {
        let counts = Dictionary(grouping: try sample(), by: \.type).mapValues(\.count)

        #expect(Set(counts.keys) == Set(CloudSchema.RecordType.allCases.map(\.rawValue)))
        #expect(counts[CloudSchema.RecordType.mural.rawValue] == 1)
        #expect(counts[CloudSchema.RecordType.freeText.rawValue] == 1)
        #expect(counts[CloudSchema.RecordType.mediaFile.rawValue] == 1)
        #expect((counts[CloudSchema.RecordType.card.rawValue] ?? 0) > 1)
    }

    @Test("A união das chaves de todos os registros é exatamente o esquema: nenhuma falta, nenhuma sobra")
    func unionOfKeysIsTheWholeSchema() throws {
        let union = CloudSchemaSample.keys(of: try sample()).values.reduce(into: Set<String>()) { $0.formUnion($1) }

        #expect(union == Set(CloudSchema.Key.allCases.map(\.rawValue)))
    }

    @Test(
        "Cada tipo de registro traz todas as chaves que pode ter, porque o esquema do CloudKit é por tipo",
        arguments: CloudSchema.RecordType.allCases)
    func eachRecordTypeHasEveryKeyItCanHave(type: CloudSchema.RecordType) throws {
        let keys = CloudSchemaSample.keys(of: try sample())

        #expect(keys[type.rawValue] == Set(type.keys.map(\.rawValue)))
    }

    @Test("As chaves saem agrupadas por tipo de registro, juntando as dos registros do mesmo tipo")
    func keysAreGroupedByRecordType() {
        func record(_ type: String, _ fields: [String: CloudValue]) -> CloudRecord {
            CloudRecord(id: CloudRecordID(zone: Self.zone, name: UUID().uuidString), type: type, fields: fields)
        }

        let keys = CloudSchemaSample.keys(of: [
            record("Card", ["kind": .string("sticky"), "x": .double(1)]),
            record("Card", ["kind": .string("text"), "tag": .string("a")]),
            record("FreeText", ["text": .string("t")]),
            record("MediaFile", [:]),
        ])

        #expect(keys == ["Card": ["kind", "x", "tag"], "FreeText": ["text"], "MediaFile": []])
        #expect(CloudSchemaSample.keys(of: []).isEmpty)
    }

    // MARK: Leitura de volta

    @Test("Os cartões voltam a ser cartões, sem `unsupported`, e reenviá-los não mudaria nenhum campo")
    func cardsDecodeBack() throws {
        let cards = try decodedCards(try sample())

        #expect(cards.count == records(.card, in: try sample()).count)
        for card in cards {
            #expect(card.item.id.uuidString == card.record.id.name)
            #expect(card.layer != nil)
            #expect(try CardRecordMapping.fields(for: card.item, layer: card.layer ?? 0) == card.record.fields)
        }
        let kinds = Set(cards.map(\.item.kind))
        #expect(kinds.isSuperset(of: [.folder, .text, .checklist, .sticky, .link, .image, .reminder, .music]))
    }

    @Test("O cartão dentro da pasta aponta para a pasta do exemplo")
    func childCardPointsToTheFolder() throws {
        let items = try decodedCards(try sample()).map(\.item)
        let folder = try #require(items.first { $0.kind == .folder })
        let children = items.filter { $0.parentID != nil }

        #expect(!children.isEmpty)
        #expect(children.allSatisfy { $0.parentID == folder.id })
    }

    @Test("O texto livre e o mural do exemplo também são lidos de volta")
    func freeTextAndBoardDecodeBack() throws {
        let records = try sample()
        let freeTextRecord = try #require(self.records(.freeText, in: records).first)
        let muralRecord = try #require(self.records(.mural, in: records).first)

        let decoding = try CardRecordMapping.freeText(from: freeTextRecord)
        guard case .freeText(let freeText) = decoding else {
            Issue.record("o texto livre veio como \(decoding)")
            return
        }
        #expect(freeText.id.uuidString == freeTextRecord.id.name)
        #expect(freeText.size != nil)
        #expect(muralRecord.id.name == CloudSchema.muralRecordName)
        #expect(CardRecordMapping.boardName(from: muralRecord) != nil)
        #expect(CardRecordMapping.boardFormatVersion(from: muralRecord) != nil)
    }

    @Test("O registro de mídia traz o arquivo dado e o cartão da imagem, com o nome do arquivo")
    func mediaRecordPointsToTheFileAndTheImageCard() throws {
        let records = try sample()
        let media = try #require(self.records(.mediaFile, in: records).first)

        let file = try #require(CardRecordMapping.mediaFile(from: media))
        #expect(file.fileName == Self.mediaFile.lastPathComponent)
        #expect(file.url == Self.mediaFile)
        let cardID = try #require(CardRecordMapping.mediaCardID(from: media))
        let image = try #require(try decodedCards(records).map(\.item).first { $0.id == cardID })
        #expect(image.kind == .image)
        #expect(image.fileName == file.fileName)
    }

    // MARK: Zona e CloudKit

    @Test("Todos os registros ficam na zona dada, e nenhum identificador se repete")
    func recordsLiveInTheGivenZone() throws {
        let records = try sample()

        #expect(records.allSatisfy { $0.id.zone == Self.zone })
        // O identificador do CloudKit é a zona e o nome, sem o tipo: dois tipos com o mesmo nome seriam o mesmo registro.
        #expect(Set(records.map(\.id)).count == records.count)
    }

    @Test("Os registros viram `CKRecord` com os mesmos campos, na zona e no tipo certos, como seguem para o CloudKit")
    func recordsConvertToCloudKit() throws {
        var keys = Set<String>()
        for record in try sample() {
            let converted = try record.makeCKRecord()

            #expect(converted.recordType == record.type)
            #expect(converted.recordID == record.id.ckRecordID)
            #expect(Set(converted.allKeys()) == Set(record.fields.keys))
            keys.formUnion(converted.allKeys())
        }
        #expect(keys == Set(CloudSchema.Key.allCases.map(\.rawValue)))
    }
}
