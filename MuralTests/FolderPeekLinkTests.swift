import Foundation
import MuralKit
import Testing

@testable import Mural

/// Links no leque da pasta: a imagem de prévia, quando guardada, faz as vezes da foto.
@Suite("Links no leque da pasta")
@MainActor
struct FolderPeekLinkTests {
    private let fileURL = { (item: BoardItem) -> URL? in URL(fileURLWithPath: "/tmp/arquivo-\(item.id.uuidString)") }

    private func link(_ title: String, previewImageFile: String?) throws -> BoardItem {
        let url = try #require(URL(string: "https://example.com/\(title)"))
        return BoardItem(kind: .link, title: title, link: LinkInfo(url: url, previewImageFile: previewImageFile))
    }

    @Test("Link com imagem de prévia guardada espia pela imagem; sem ela, pelo título")
    func linkUsesItsPreviewImage() throws {
        let withImage = try link("Com imagem", previewImageFile: "capa.jpg")
        let withoutImage = try link("Sem imagem", previewImageFile: nil)
        let preview = URL(fileURLWithPath: "/tmp/LinkPreviews/capa.jpg")

        let peeks = FolderPeekItem.latest(
            [withImage, withoutImage], fileURL: fileURL,
            linkPreviewURL: { $0.link?.previewImageFile == "capa.jpg" ? preview : nil })

        #expect(peeks.map(\.kind) == [.link, .link])
        #expect(peeks.map(\.title) == ["Com imagem", "Sem imagem"])
        #expect(peeks.map(\.fileURL) == [preview, nil])
    }

    @Test("Só o link pede a imagem de prévia; foto e nota seguem como antes")
    func onlyLinksAskForThePreview() throws {
        let photo = BoardItem(kind: .image, title: "Foto", fileName: "foto.jpg")
        let note = BoardItem(kind: .text, title: "Nota", text: "corpo")
        var asked: [UUID] = []

        let peeks = FolderPeekItem.latest(
            [photo, note, try link("Link", previewImageFile: "capa.jpg")], fileURL: fileURL,
            linkPreviewURL: { item in
                asked.append(item.id)
                return nil
            })

        #expect(asked == [peeks[2].id])
        #expect(peeks[0].fileURL == fileURL(photo))
        #expect(peeks[1].fileURL == nil)
        #expect(peeks[2].fileURL == nil, "sem a imagem guardada, o link espia pelo título")
    }

    @Test("Sem quem procure a imagem de prévia, o link espia pelo título")
    func defaultHasNoPreview() throws {
        let peeks = FolderPeekItem.latest([try link("Link", previewImageFile: "capa.jpg")], fileURL: fileURL)

        #expect(peeks.first?.fileURL == nil)
    }
}
