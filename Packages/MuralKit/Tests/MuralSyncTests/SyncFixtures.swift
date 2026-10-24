import Foundation
import MuralKit
import MuralSync

/// Cartões e registros de exemplo dos testes do MuralSync.
enum SyncFixtures {
    /// Datas com tantas casas decimais quanto um `Double` guarda nessa grandeza: a ida e volta prova que nada é arredondado.
    static let fractionalDate = Date(timeIntervalSinceReferenceDate: 779_123_456.123_456_789)
    static let otherFractionalDate = Date(timeIntervalSinceReferenceDate: 780_000_000.987_654_321)
    static let thirdFractionalDate = Date(timeIntervalSinceReferenceDate: 781_234_567.000_000_123)

    static let zone = CloudZoneID(name: "mural-5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01")

    static func record(_ type: CloudSchema.RecordType, name: String, fields: [String: CloudValue]) -> CloudRecord {
        CloudRecord(id: CloudRecordID(zone: zone, name: name), type: type.rawValue, fields: fields)
    }

    /// O registro de um cartão, como o motor de verdade o montaria.
    static func cardRecord(_ item: BoardItem, layer: Double = 1) throws -> CloudRecord {
        record(.card, name: item.id.uuidString, fields: try CardRecordMapping.fields(for: item, layer: layer))
    }

    /// O que os campos pesam no limite do registro, contado de novo aqui (e não com o código testado): textos em UTF-8 e dados.
    static func payloadBytes(of fields: [String: CloudValue]) -> Int {
        fields.values.reduce(0) { total, value in
            switch value {
            case .string(let text): total + text.utf8.count
            case .data(let data): total + data.count
            case .int, .double, .asset: total
            }
        }
    }

    /// Um cartão com todos os campos opcionais preenchidos, também os que são só de cada Mac e por isso não viajam. Vale para
    /// qualquer tipo: a tradução é campo a campo e não depende de o campo fazer sentido naquele tipo.
    static func fullItem(kind: ItemKind, id: UUID = UUID()) -> BoardItem {
        BoardItem(
            id: id,
            kind: kind,
            title: "Título de \(kind.rawValue) com \"aspas\", acentuação e emoji 🙂",
            createdAt: fractionalDate,
            parentID: UUID(uuidString: "11111111-2222-3333-4444-555555555555"),
            position: BoardPoint(x: 120.5, y: -33.25),
            fileName: "AAAAAAAA-0000-4000-8000-000000000001.jpg",
            text: "Corpo em\nduas linhas, com barra \\ e tabulação\t.",
            caption: "Legenda da imagem",
            checklist: ChecklistDocument(
                title: "Mercado",
                intro: "Sábado de manhã",
                sections: [
                    ChecklistSection(
                        title: "Frutas",
                        entries: [ChecklistEntry(text: "Maçã", isDone: true), ChecklistEntry(text: "Pêra")])
                ]),
            stickyColor: .pink,
            imageMetadata: ImageMetadata(
                pixelWidth: 4032, pixelHeight: 3024, fileSizeBytes: 2_345_678, colorProfile: "Display P3",
                palette: [PaletteColor(red: 0.1, green: 0.2, blue: 0.3), PaletteColor(red: 0.9, green: 0.8, blue: 0.7)]),
            tag: "CLIENT 001",
            keySentences: KeySentenceRecord(source: "Corpo em duas linhas.", choices: [:]),
            link: LinkInfo(
                url: URL(string: "https://example.com/a?b=c#d")!,
                pageTitle: "Página de exemplo",
                siteName: "Exemplo",
                summary: "Resumo da página",
                remoteImageURL: URL(string: "https://example.com/i.png"),
                previewImageFile: "previa.jpg",
                iconFile: "icone.png",
                preview: .ready(fetchedAt: otherFractionalDate)),
            reminder: ReminderSnapshot(
                identifier: "ABC-1",
                externalIdentifier: "EXT-1",
                title: "Pagar a conta",
                notes: "Antes do vencimento",
                dueDate: otherFractionalDate,
                dueHasTime: true,
                isCompleted: true,
                completionDate: thirdFractionalDate,
                priority: 5,
                listTitle: "Casa",
                listColorHex: "#112233",
                url: URL(string: "https://example.com/conta"),
                isMissing: true),
            music: MusicSnapshot(
                kind: .album,
                catalogID: "1234",
                storefront: "br",
                libraryPlaylistName: "Minha lista",
                libraryID: "LIB-1",
                url: URL(string: "https://music.apple.com/br/album/x/1234"),
                title: "Álbum",
                subtitle: "Artista",
                albumTitle: "Álbum",
                artworkTemplate: "https://example.com/{w}x{h}.{f}",
                artworkFile: "capa.jpg",
                backgroundHex: "#112233",
                primaryTextHex: "#ffffff",
                secondaryTextHex: "#eeeeee",
                trackCount: 12,
                releaseDate: "2024-05-01",
                duration: 215.123_456),
            colorTag: .purple,
            attachments: [NoteAttachment(fileName: "AAAAAAAA-0000-4000-8000-000000000002.png", pixelWidth: 640, pixelHeight: 480)],
            folderPosition: BoardPoint(x: -12, y: 48.5),
            size: BoardSize(width: 210.5, height: 160.25))
    }
}
