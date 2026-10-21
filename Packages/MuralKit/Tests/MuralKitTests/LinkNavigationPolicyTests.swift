import Foundation
import Testing

@testable import MuralKit

@Suite("Regras de navegação da página do link")
struct LinkNavigationPolicyTests {
    private let page = URL(string: "https://example.com/artigo?id=1")!
    private let insecurePage = URL(string: "http://example.com/artigo")!
    private let mail = URL(string: "mailto:contato@example.com?subject=Oi")!

    /// Atalho: `decide` com tudo desligado, menos o que o teste liga.
    private func decide(
        _ url: URL?, mainFrame: Bool = true, newWindow: Bool = false, download: Bool = false, userInitiated: Bool = true
    ) -> LinkNavigationPolicy.Decision {
        LinkNavigationPolicy.decide(
            url: url, isMainFrame: mainFrame, opensNewWindow: newWindow, shouldDownload: download, isUserInitiated: userInitiated)
    }

    // MARK: Web

    @Test("Página da web no quadro principal continua no app")
    func webPageInMainFrameIsAllowed() {
        #expect(decide(page) == .allow)
        #expect(decide(insecurePage) == .allow)
    }

    @Test("Página da web num quadro embutido continua no app")
    func webPageInSubframeIsAllowed() {
        #expect(decide(page, mainFrame: false) == .allow)
    }

    @Test("Esquema em maiúsculas é reconhecido")
    func schemeIsCaseInsensitive() {
        let upper = URL(string: "HTTPS://Example.com/")!
        #expect(decide(upper) == .allow)
        #expect(decide(upper, mainFrame: false, newWindow: true) == .openExternally(upper))
        #expect(decide(URL(string: "MAILTO:a@example.com")!) == .openExternally(URL(string: "MAILTO:a@example.com")!))
    }

    @Test("Janela nova com endereço da web vai para o navegador")
    func newWindowOpensInBrowser() {
        #expect(decide(page, mainFrame: false, newWindow: true) == .openExternally(page))
        #expect(decide(insecurePage, mainFrame: false, newWindow: true) == .openExternally(insecurePage))
        // Mesmo marcada como quadro principal, a janela nova vence.
        #expect(decide(page, mainFrame: true, newWindow: true) == .openExternally(page))
    }

    @Test("Download de endereço da web vai para o navegador")
    func downloadOpensInBrowser() {
        #expect(decide(page, download: true) == .openExternally(page))
        #expect(decide(page, mainFrame: false, download: true) == .openExternally(page))
        #expect(decide(page, newWindow: true, download: true) == .openExternally(page))
    }

    @Test("Endereço http ou https sem host é descartado")
    func webSchemeWithoutHostIsCancelled() {
        #expect(decide(URL(string: "https:///caminho")!) == .cancel)
        #expect(decide(URL(string: "http:")!) == .cancel)
    }

    // MARK: Fora da web

    @Test(
        "Esquema de fora da web no quadro principal vai para o sistema",
        arguments: [
            "mailto:contato@example.com", "tel:+5521999999999", "sms:+5521999999999", "facetime://contato@example.com",
            "itms-apps://apps.apple.com/app/id1", "zoommtg://zoom.us/join?confno=1", "slack://channel?team=T1&id=C1",
        ])
    func appSchemesInMainFrameOpenExternally(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(decide(url) == .openExternally(url))
    }

    @Test("Esquema de fora da web em janela nova também vai para o sistema")
    func appSchemesInNewWindowOpenExternally() {
        #expect(decide(mail, mainFrame: false, newWindow: true) == .openExternally(mail))
    }

    @Test("Esquema de fora da web num quadro embutido é permitido, porque a página inteira é que decide sair do app")
    func appSchemesInSubframeAreAllowed() {
        #expect(decide(mail, mainFrame: false) == .allow)
        #expect(decide(URL(string: "slack://channel?team=T1")!, mainFrame: false) == .allow)
    }

    @Test(
        "about:, data: e blob: num quadro embutido são permitidos",
        arguments: ["about:blank", "about:srcdoc", "data:text/html,oi", "blob:https://example.com/1234"])
    func internalSchemesInSubframeAreAllowed(address: String) throws {
        let url = try #require(URL(string: address))
        #expect(decide(url, mainFrame: false) == .allow)
    }

    @Test("about:blank no quadro principal é permitido: é o endereço do HTML local carregado direto no app")
    func aboutBlankInMainFrameIsAllowed() {
        #expect(decide(URL(string: "about:blank")!) == .allow)
    }

    @Test("data:, blob: e javascript: no quadro principal ficam no WebKit e não vão para o sistema")
    func internalSchemesInMainFrameStayInTheWebKit() throws {
        for address in ["data:text/html,oi", "blob:https://example.com/1234", "javascript:void(0)"] {
            let url = try #require(URL(string: address))
            #expect(decide(url) == .allow, "\(address)")
        }
    }

    @Test("about:, data:, blob: e javascript: em janela nova são descartados")
    func internalSchemesInNewWindowAreCancelled() throws {
        for address in ["about:blank", "data:text/html,oi", "blob:https://example.com/1234", "javascript:void(0)"] {
            let url = try #require(URL(string: address))
            #expect(decide(url, mainFrame: false, newWindow: true) == .cancel, "\(address)")
        }
    }

    @Test("file: nunca é carregado nem aberto")
    func fileSchemeIsAlwaysCancelled() {
        let file = URL(string: "file:///System/Applications/Calculator.app")!
        #expect(decide(file) == .cancel)
        #expect(decide(file, mainFrame: false) == .cancel)
        #expect(decide(file, mainFrame: false, newWindow: true) == .cancel)
        #expect(decide(file, download: true) == .cancel)
    }

    @Test("Download de fora da web é descartado")
    func downloadOfNonWebAddressIsCancelled() {
        let blob = URL(string: "blob:https://example.com/1234")!
        #expect(decide(blob, download: true) == .cancel)
        #expect(decide(mail, download: true) == .cancel)
    }

    @Test("Sem endereço, descarta")
    func missingAddressIsCancelled() {
        #expect(decide(nil) == .cancel)
        #expect(decide(nil, mainFrame: false, newWindow: true) == .cancel)
        #expect(decide(nil, download: true) == .cancel)
    }

    // MARK: Pedido da própria página

    @Test("A página não abre janela nem baixa arquivo por conta própria")
    func scriptedNewWindowAndDownloadAreCancelled() {
        #expect(decide(page, mainFrame: false, newWindow: true, userInitiated: false) == .cancel)
        #expect(decide(page, download: true, userInitiated: false) == .cancel)
    }

    @Test("A página não abre outro app por conta própria")
    func scriptedAppSchemeIsCancelled() {
        #expect(decide(mail, userInitiated: false) == .cancel)
        #expect(decide(mail, mainFrame: false, newWindow: true, userInitiated: false) == .cancel)
    }

    @Test("Redirecionamento da própria página para outra página da web continua no app")
    func scriptedWebNavigationIsAllowed() {
        #expect(decide(page, userInitiated: false) == .allow)
        #expect(decide(page, mainFrame: false, userInitiated: false) == .allow)
    }

    @Test("Sem dizer quem pediu, o pedido conta como da pessoa")
    func userInitiatedDefaultsToTrue() {
        #expect(
            LinkNavigationPolicy.decide(url: mail, isMainFrame: true, opensNewWindow: false, shouldDownload: false) == .openExternally(mail)
        )
        #expect(
            LinkNavigationPolicy.decide(url: page, isMainFrame: false, opensNewWindow: true, shouldDownload: false) == .openExternally(page)
        )
    }

    // MARK: Resposta

    @Test("Resposta que o WebKit sabe mostrar continua na página")
    func showableResponseIsAllowed() {
        #expect(LinkNavigationPolicy.decide(canShowMimeType: true, url: page) == .allow)
        #expect(LinkNavigationPolicy.decide(canShowMimeType: true, url: nil) == .allow)
    }

    @Test("Resposta que o WebKit não sabe mostrar vai para o navegador")
    func unshowableResponseOpensInBrowser() {
        #expect(LinkNavigationPolicy.decide(canShowMimeType: false, url: page) == .openExternally(page))
    }

    @Test("Resposta que não dá para mostrar nem entregar ao navegador é descartada")
    func unshowableResponseWithoutWebAddressIsCancelled() {
        #expect(LinkNavigationPolicy.decide(canShowMimeType: false, url: nil) == .cancel)
        #expect(LinkNavigationPolicy.decide(canShowMimeType: false, url: URL(string: "blob:https://example.com/1")!) == .cancel)
        #expect(LinkNavigationPolicy.decide(canShowMimeType: false, url: URL(string: "file:///tmp/a.zip")!) == .cancel)
    }
}
