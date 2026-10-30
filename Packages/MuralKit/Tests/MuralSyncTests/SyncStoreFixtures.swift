import Foundation
import MuralKit
import MuralSync

/// Estados de sincronização de exemplo, para os testes do `SyncMetadataStore`.
extension SyncFixtures {
    /// Um mural de outra pessoa, que esta pode editar.
    static let cloudInfo = BoardCloudInfo(
        database: .shared,
        zoneName: "mural-5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01",
        zoneOwnerName: "_d41d8cd98f00b204e9800998ecf8427e",
        ownerDisplayName: "Ana",
        permission: .readWrite)

    /// Um mural com um cartão de cada tipo, só com os campos que fazem sentido em cada um, e um texto livre. Os cartões estão na
    /// forma compartilhada, como a base do iCloud os guarda. Uma imagem leva legenda e não texto: é assim que o formato a grava, e
    /// o `BoardItem` passa para a legenda o texto que uma imagem antiga tinha.
    static func realisticBoard() -> Board {
        let folder = BoardItem(
            kind: .folder, title: "Casa", createdAt: fractionalDate, position: BoardPoint(x: 40, y: 60), tag: "CASA", colorTag: .blue)
        let subfolder = BoardItem(kind: .folder, title: "Cozinha", createdAt: otherFractionalDate, parentID: folder.id)
        let sticky = BoardItem(
            kind: .sticky, title: "Tinta", createdAt: thirdFractionalDate, parentID: folder.id, text: "Tinta azul", stickyColor: .yellow,
            folderPosition: BoardPoint(x: 8, y: 40))
        let note = BoardItem(
            kind: .text, title: "Nota", createdAt: fractionalDate, position: BoardPoint(x: 300, y: 80.5),
            text: "Texto da nota\ncom 2 linhas",
            attachments: [NoteAttachment(fileName: "AAAAAAAA-0000-4000-8000-000000000002.png", pixelWidth: 640, pixelHeight: 480)])
        let image = BoardItem(
            kind: .image, title: "Foto", createdAt: otherFractionalDate, position: BoardPoint(x: 10, y: 300),
            fileName: "AAAAAAAA-0000-4000-8000-000000000001.jpg", caption: "Legenda",
            imageMetadata: ImageMetadata(
                pixelWidth: 4032, pixelHeight: 3024, fileSizeBytes: 2_345_678, colorProfile: "Display P3",
                palette: [PaletteColor(red: 0.1, green: 0.2, blue: 0.3)]))
        let video = BoardItem(kind: .video, title: "Filme", fileName: "AAAAAAAA-0000-4000-8000-000000000003.mov")
        let pdf = BoardItem(kind: .pdf, title: "Contrato", fileName: "AAAAAAAA-0000-4000-8000-000000000004.pdf")
        let list = BoardItem(
            kind: .checklist, title: "Mercado",
            checklist: ChecklistDocument(
                title: "Mercado", intro: "Sábado",
                sections: [ChecklistSection(title: "Frutas", entries: [ChecklistEntry(text: "Maçã", isDone: true)])]))
        let link = BoardItem(
            kind: .link, title: "Site",
            link: LinkInfo(
                url: URL(string: "https://example.com/a?b=c")!, pageTitle: "Página", siteName: "Exemplo", summary: "Resumo",
                remoteImageURL: URL(string: "https://example.com/i.png")))
        let reminder = BoardItem(
            kind: .reminder, title: "Pagar",
            reminder: ReminderSnapshot(
                identifier: "ABC", title: "Pagar", dueDate: otherFractionalDate, dueHasTime: true, priority: 1, listTitle: "Casa"))
        let music = BoardItem(
            kind: .music, title: "Álbum",
            music: MusicSnapshot(kind: .album, catalogID: "1234", title: "Álbum", subtitle: "Artista", duration: 215.5))
        let contact = BoardItem(
            kind: .contact, title: "Fulana de Tal",
            contact: ContactSnapshot(
                givenName: "Fulana", familyName: "de Tal", phones: [LabeledValue(label: "celular", value: "+55 21 99999-0000")]))
        let freeText = BoardFreeText(text: "Oi", position: BoardPoint(x: 5, y: 6), createdAt: fractionalDate)
        return Board(
            items: [folder, subfolder, sticky, note, image, video, pdf, list, link, reminder, music, contact], freeTexts: [freeText])
    }

    /// O estado de um mural já enviado, com tudo preenchido.
    static func syncState(board: Board = realisticBoard()) -> BoardSyncState {
        var layers: [UUID: Double] = [:]
        var systemFields: [String: Data] = [CloudSchema.muralRecordName: Data(repeating: 0xAB, count: 300)]
        for (index, item) in board.items.enumerated() {
            layers[item.id] = Double(index) + 0.5
            systemFields[item.id.uuidString] = Data([0x62, 0x70, UInt8(index)])
        }
        let uploaded = ["AAAAAAAA-0000-4000-8000-000000000001.jpg", "AAAAAAAA-0000-4000-8000-000000000002.png"]
        var owners: [String: UUID] = [:]
        for file in uploaded {
            if let owner = board.items.first(where: { $0.assetFileNames.contains(file) }) { owners[file] = owner.id }
        }
        return BoardSyncState(
            cloud: cloudInfo,
            base: board,
            baseName: "Casa 🏠",
            baseBoardFormatVersion: board.requiredFormatVersion,
            layers: layers,
            systemFields: systemFields,
            uploadedFiles: Set(uploaded),
            mediaOwners: owners,
            unsupportedRecordNames: ["11111111-2222-3333-4444-555555555555", "99999999-8888-7777-6666-555555555555"])
    }
}
