import Foundation
import MuralKit
import Testing

@testable import Mural

@MainActor
struct LinkDisplayTests {
    @Test("O nome do site é o declarado pela página ou, sem ele, o host do endereço")
    func siteNameFallsBackToHost() throws {
        let url = try #require(URL(string: "https://www.Apple.com/br/mac"))

        #expect(LinkInfo(url: url).displayHost == "apple.com")
        #expect(LinkInfo(url: url).displaySiteName == "apple.com")
        #expect(LinkInfo(url: url, siteName: "Apple (Brasil)").displaySiteName == "Apple (Brasil)")
        #expect(LinkInfo(url: url, siteName: "Apple (Brasil)").displayHost == "apple.com")
    }

    @Test(
        "Só cartões de link com endereço http ou https abrem no navegador",
        arguments: [
            ("https://apple.com", true), ("http://apple.com/mac?x=1", true), ("HTTPS://Apple.com", true),
            ("file:///Applications/Calculator.app", false), ("javascript:alert(1)", false),
            ("x-apple.systempreferences:com.apple.preference.security", false), ("ftp://apple.com/arquivo.zip", false),
            ("mailto:someone@example.com", false),
        ])
    func onlyWebAddressesOpenInTheBrowser(address: String, opens: Bool) throws {
        let url = try #require(URL(string: address))
        let item = BoardItem(kind: .link, title: "Link", link: LinkInfo(url: url))

        #expect((item.browserURL != nil) == opens)
        if opens { #expect(item.browserURL == url) }
    }

    @Test("Cartão que não é de link, ou sem dados de link, não tem endereço para o navegador")
    func nonLinkItemsHaveNoBrowserURL() throws {
        let url = try #require(URL(string: "https://apple.com"))

        #expect(BoardItem(kind: .text, title: "Nota", text: "https://apple.com").browserURL == nil)
        #expect(BoardItem(kind: .link, title: "Sem dados").browserURL == nil)
        // Os dados de link só valem num cartão de link.
        #expect(BoardItem(kind: .sticky, title: "Post-it", link: LinkInfo(url: url)).browserURL == nil)
    }

    @Test("O aviso de apagar um link fala da prévia guardada e garante que a página não é afetada")
    func deleteWarningForLink() throws {
        let url = try #require(URL(string: "https://apple.com"))
        let link = BoardItem(kind: .link, title: "Apple", link: LinkInfo(url: url))

        #expect(
            ItemKind.deleteWarning(for: link, childCount: 0)
                == "O cartão e a prévia guardada pelo Mural serão removidos. A página original não é afetada.")
    }

    @Test("Os avisos de apagar dos outros tipos continuam como eram")
    func deleteWarningForOtherKinds() {
        let file = "O cartão e o arquivo guardado pelo Mural serão removidos. O arquivo original não é tocado."
        let image = BoardItem(kind: .image, title: "Foto", fileName: "foto.png")
        let folder = BoardItem(kind: .folder, title: "Pasta")

        #expect(ItemKind.deleteWarning(for: image, childCount: 0) == file)
        #expect(ItemKind.deleteWarning(for: BoardItem(kind: .text, title: "Nota"), childCount: 0) == file)
        #expect(ItemKind.deleteWarning(for: folder, childCount: 0) == "A pasta vazia será removida.")
        #expect(ItemKind.deleteWarning(for: folder, childCount: 1) == "A pasta e o item dentro dela serão removidos.")
        #expect(ItemKind.deleteWarning(for: folder, childCount: 3) == "A pasta e os 3 itens dentro dela serão removidos.")
    }
}
