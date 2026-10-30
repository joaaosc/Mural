import Foundation
import MuralKit

/// Um mural de exemplo com todos os tipos de registro e todas as chaves do esquema do iCloud, para gravar uma vez no ambiente de
/// desenvolvimento antes de publicar o esquema em produção. Não é um mural de verdade: a zona é apagada logo depois.
///
/// O CloudKit de desenvolvimento cria cada campo na primeira gravação de um registro que o traz, e `CardRecordMapping` só grava a
/// chave de um valor presente. Por isso o exemplo tem um cartão de cada tipo, com os campos opcionais preenchidos. Chave nova em
/// `CloudSchema.Key` precisa de um valor aqui; os testes avisam quando falta.
public enum CloudSchemaSample {
    private static let baseDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Os registros do exemplo na zona dada: o do mural, um por cartão, um texto livre e um arquivo de mídia. O registro de mídia e o
    /// cartão de imagem levam o nome de `mediaFile`, e o `file` aponta para ele: quem grava cria o arquivo antes.
    public static func records(in zone: CloudZoneID, mediaFile: URL) throws -> [CloudRecord] {
        let imageID = UUID()
        let fileName = mediaFile.lastPathComponent
        let freeText = BoardFreeText(
            text: "Texto livre de exemplo", position: BoardPoint(x: 40, y: 520), createdAt: baseDate.addingTimeInterval(10),
            size: BoardSize(width: 240, height: 120))
        let board = Board(items: items(imageID: imageID, imageFileName: fileName), freeTexts: [freeText])

        var records = [
            record(.mural, CloudSchema.muralRecordName, in: zone, CardRecordMapping.boardFields(name: "Exemplo do esquema", board: board))
        ]
        for (index, item) in board.items.enumerated() {
            // O empilhamento começa em 1 e segue a ordem da lista.
            let fields = try CardRecordMapping.fields(for: item, layer: Double(index + 1))
            records.append(record(.card, item.id.uuidString, in: zone, fields))
        }
        records.append(record(.freeText, freeText.id.uuidString, in: zone, CardRecordMapping.fields(for: freeText)))
        records.append(record(.mediaFile, fileName, in: zone, CardRecordMapping.mediaFields(fileURL: mediaFile, cardID: imageID)))
        return records
    }

    /// As chaves que os registros do exemplo trazem, por tipo de registro; os testes conferem que cobrem `CloudSchema.Key.allCases`.
    public static func keys(of records: [CloudRecord]) -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for record in records {
            result[record.type, default: []].formUnion(record.fields.keys)
        }
        return result
    }

    private static func record(
        _ type: CloudSchema.RecordType, _ name: String, in zone: CloudZoneID, _ fields: [String: CloudValue]
    ) -> CloudRecord {
        CloudRecord(id: CloudRecordID(zone: zone, name: name), type: type.rawValue, fields: fields)
    }

    /// Os cartões do exemplo, na ordem do empilhamento: a pasta, o post-it que está dentro dela e um cartão de cada tipo que guarda
    /// algo próprio, em duas fileiras no mural.
    private static func items(imageID: UUID, imageFileName: String) -> [BoardItem] {
        let folderID = UUID()
        func date(_ offset: TimeInterval) -> Date { baseDate.addingTimeInterval(offset) }
        func place(_ column: Double, _ row: Double) -> BoardPoint { BoardPoint(x: 40 + 280 * column, y: 40 + 240 * row) }

        return [
            BoardItem(
                id: folderID, kind: .folder, title: "Pasta de exemplo", createdAt: date(0), position: place(0, 0), tag: "EXEMPLO",
                colorTag: .blue),
            BoardItem(
                kind: .sticky, title: "Post-it na pasta", createdAt: date(1), parentID: folderID, text: "Post-it solto dentro da pasta.",
                stickyColor: .pink, folderPosition: BoardPoint(x: -30, y: 60)),
            BoardItem(
                kind: .text, title: "Nota de exemplo", createdAt: date(2), position: place(1, 0), text: "Nota com uma imagem colada.",
                attachments: [NoteAttachment(fileName: "\(UUID().uuidString).png", pixelWidth: 640, pixelHeight: 480)]),
            BoardItem(
                kind: .checklist, title: "Lista de exemplo", createdAt: date(3), position: place(2, 0),
                checklist: ChecklistDocument(
                    title: "Lista de exemplo", intro: "Uma lista com um item feito.",
                    sections: [
                        ChecklistSection(
                            title: "Seção de exemplo",
                            entries: [ChecklistEntry(text: "Item feito", isDone: true), ChecklistEntry(text: "Item aberto")])
                    ])),
            BoardItem(
                kind: .sticky, title: "Post-it maior", createdAt: date(4), position: place(3, 0), text: "Post-it com tamanho escolhido.",
                stickyColor: .yellow, size: BoardSize(width: 240, height: 200)),
            BoardItem(
                kind: .link, title: "Link de exemplo", createdAt: date(5), position: place(0, 1),
                link: LinkInfo(
                    url: URL(string: "https://example.com/pagina")!, pageTitle: "Página de exemplo", siteName: "Exemplo",
                    summary: "Resumo da página de exemplo.", remoteImageURL: URL(string: "https://example.com/imagem.jpg"))),
            BoardItem(
                id: imageID, kind: .image, title: "Imagem de exemplo", createdAt: date(6), position: place(1, 1), fileName: imageFileName,
                caption: "Legenda da imagem.",
                imageMetadata: ImageMetadata(
                    pixelWidth: 1600, pixelHeight: 1200, fileSizeBytes: 345_678, colorProfile: "Display P3",
                    palette: [PaletteColor(red: 0.9, green: 0.8, blue: 0.7), PaletteColor(red: 0.1, green: 0.2, blue: 0.3)])),
            BoardItem(
                kind: .reminder, title: "Lembrete de exemplo", createdAt: date(7), position: place(2, 1),
                reminder: ReminderSnapshot(
                    identifier: "EXEMPLO-1", externalIdentifier: "EXEMPLO-EXT-1", title: "Lembrete de exemplo",
                    notes: "Notas do lembrete.", dueDate: date(86_400), dueHasTime: true, isCompleted: true,
                    completionDate: date(90_000), priority: 5, listTitle: "Casa", listColorHex: "#336699",
                    url: URL(string: "https://example.com/lembrete"))),
            BoardItem(
                kind: .music, title: "Música de exemplo", createdAt: date(8), position: place(3, 1),
                music: MusicSnapshot(
                    kind: .album, catalogID: "1234567890", storefront: "br",
                    url: URL(string: "https://music.apple.com/br/album/exemplo/1234567890"), title: "Álbum de exemplo",
                    subtitle: "Artista de exemplo", albumTitle: "Álbum de exemplo",
                    artworkTemplate: "https://example.com/{w}x{h}.{f}", backgroundHex: "#223344", primaryTextHex: "#ffffff",
                    secondaryTextHex: "#dddddd", trackCount: 12, releaseDate: "2024-05-01", duration: 215.5)),
            BoardItem(
                kind: .contact, title: "Fulana de Tal", createdAt: date(9), position: place(4, 1),
                contact: ContactSnapshot(
                    givenName: "Fulana", familyName: "de Tal", organization: "Empresa de exemplo",
                    phones: [LabeledValue(label: "celular", value: "+55 21 99999-0000")],
                    emails: [LabeledValue(label: "trabalho", value: "fulana@example.com")])),
        ]
    }
}
