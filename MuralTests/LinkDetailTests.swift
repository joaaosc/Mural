import Foundation
import Testing

@testable import Mural

/// Partes do detalhe do link que não dependem de abrir uma página: nenhum destes testes carrega nada no WebKit.
@MainActor
struct LinkDetailTests {
    @Test("Só os testes de interface evitam a rede: eles mostram a página local de exemplo")
    func livePagesFollowLaunchArguments() {
        #expect(LaunchConfiguration.loadsLivePages(arguments: []))
        #expect(LaunchConfiguration.loadsLivePages(arguments: ["-quiet"]))
        for argument in ["-uiTesting", "-uiTestingKeep"] {
            #expect(!LaunchConfiguration.loadsLivePages(arguments: ["-quiet", argument]))
        }
    }

    @Test("A página de exemplo tem o título que o teste de interface procura e não busca nada na rede")
    func fixturePageHasTheTitleAndNoRemoteContent() {
        let html = FixtureLinkPage.html

        #expect(FixtureLinkPage.title == "Página de exemplo")
        #expect(html.contains("<title>Página de exemplo</title>"))
        #expect(html.contains("<h1>Página de exemplo</h1>"))
        #expect(!html.contains("http://") && !html.contains("https://") && !html.contains("src="))
    }

    @Test("Cancelar uma navegação, ou interrompê-la por mudança de política, não é falha da página")
    func cancellationsAreNotFailures() {
        #expect(LinkPageController.isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        #expect(LinkPageController.isCancellation(NSError(domain: "WebKitErrorDomain", code: 102)))
    }

    @Test(
        "Sem rede, host inexistente, tempo esgotado e conexão insegura são falhas da página",
        arguments: [
            NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorTimedOut, NSURLErrorCannotConnectToHost,
            NSURLErrorServerCertificateUntrusted, NSURLErrorAppTransportSecurityRequiresSecureConnection,
        ])
    func networkErrorsAreFailures(code: Int) {
        #expect(!LinkPageController.isCancellation(NSError(domain: NSURLErrorDomain, code: code)))
    }

    @Test("Um erro de outro domínio com o código de cancelamento não é cancelamento")
    func cancellationCodeInAnotherDomainIsAFailure() {
        #expect(!LinkPageController.isCancellation(NSError(domain: "OutroDominio", code: NSURLErrorCancelled)))
        #expect(!LinkPageController.isCancellation(NSError(domain: "WebKitErrorDomain", code: 101)))
    }

    @Test("Cartão sem endereço da web não cria página: mostra o erro e desliga o que depende de página")
    func cardWithoutWebAddressShowsFailure() {
        let controller = LinkPageController()

        controller.start(url: nil, source: .web)

        #expect(controller.page == nil)
        #expect(controller.failure != nil)
        #expect(controller.failure?.url == nil)
        #expect(controller.browserURL == nil)
        #expect(!controller.canGoBack)
        #expect(!controller.canGoForward)
        #expect(!controller.canUseAsPreview)
    }
}
