import Foundation
import MuralKit
import Synchronization
import Testing

@testable import Mural

/// Nenhum destes testes usa a rede: as requisições vão para o `StubServer` de cada teste.
struct SystemLinkPreviewFetcherTests {
    private static let imageLimit = SystemLinkPreviewFetcher.imageByteLimit
    private static let iconLimit = SystemLinkPreviewFetcher.iconByteLimit
    private static let pageLimit = SystemLinkPreviewFetcher.pageByteLimit

    // MARK: Página

    @Test("Uma página com og: dá título, resumo, site, imagem e ícone, e a reserva não é chamada")
    func openGraphPageGivesEverything() async throws {
        let server = StubServer()
        let image = try TestImage.png(width: 400, height: 210)
        let icon = try TestImage.png(width: 64, height: 64)
        server.respond("/artigo", html: StubPage.html(image: "/capa.png", icons: ["/icone.png"]))
        server.respond("/capa.png", image: image)
        server.respond("/icone.png", image: icon)
        let probe = FallbackProbe()

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/artigo"))

        #expect(preview.title == "Título da página")
        #expect(preview.summary == "Resumo da página")
        #expect(preview.siteName == "Site de teste")
        #expect(preview.imageData == image)
        #expect(preview.remoteImageURL == server.url("/capa.png"))
        #expect(preview.iconData == icon)
        #expect(probe.urls.isEmpty, "com título e imagem a reserva não é chamada")
        #expect(server.requestedPaths == ["/artigo", "/capa.png", "/icone.png"])
    }

    @Test("A sessão padrão pede HTML e envia os idiomas do usuário; imagens e ícones pedem imagem")
    func requestsCarryAcceptHeaders() async throws {
        let server = StubServer()
        server.respond("/artigo", html: StubPage.html(image: "/capa.png"))
        server.respond("/capa.png", image: try TestImage.png(width: 400, height: 210))

        _ = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        let page = try #require(server.requests.first)
        #expect(page.headers["Accept-Language"] == "pt-BR, en;q=0.9")
        #expect(page.headers["Accept"]?.hasPrefix("text/html") == true)
        let image = try #require(server.requests.dropFirst().first)
        #expect(image.headers["Accept"]?.hasPrefix("image/") == true)
    }

    @Test("A URL final, depois de um redirecionamento, é a base dos endereços relativos")
    func finalURLIsTheBaseOfRelativeAddresses() async throws {
        let server = StubServer()
        let image = try TestImage.png(width: 400, height: 210)
        let icon = try TestImage.png(width: 64, height: 64)
        server.respond("/curto", StubServer.Reply(redirect: "/artigos/final/"))
        server.respond("/artigos/final/", html: StubPage.html(image: "capa.png", icons: ["../icone.png"]))
        server.respond("/artigos/final/capa.png", image: image)
        server.respond("/artigos/icone.png", image: icon)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/curto"))

        #expect(preview.remoteImageURL == server.url("/artigos/final/capa.png"))
        #expect(preview.imageData == image)
        #expect(preview.iconData == icon)
    }

    @Test("A leitura da página para no </head>, sem esperar o resto do corpo")
    func pageReadingStopsAtTheEndOfTheHead() async throws {
        let server = StubServer()
        var reply = StubServer.Reply(body: Data(StubPage.html(image: nil).utf8))
        reply.staysOpen = true
        server.respond("/artigo", reply)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.title == "Título da página")
        await waitUntil("a transferência da página ser interrompida") { server.interruptedPaths.contains("/artigo") }
    }

    @Test("Sem </head>, a página é lida só até 512 KB")
    func pageReadingStopsAt512KB() async throws {
        let server = StubServer()
        // O título vem cedo; a descrição, depois dos 512 KB, não chega a ser lida.
        let filler = String(repeating: "x", count: Self.pageLimit)
        let html = "<head><title>Título cedo</title><!-- \(filler) --><meta property=\"og:description\" content=\"Tarde demais\">"
        var reply = StubServer.Reply(body: Data(html.utf8))
        reply.staysOpen = true
        server.respond("/artigo", reply)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.title == "Título cedo")
        #expect(preview.summary == nil)
        await waitUntil("a transferência da página ser interrompida") { server.interruptedPaths.contains("/artigo") }
    }

    @Test("Uma página que não é HTML nem imagem não é lida; a reserva completa")
    func otherContentTypesAreSkipped() async throws {
        let server = StubServer()
        var reply = StubServer.Reply(contentType: "application/pdf", body: Data("%PDF-1.7".utf8))
        reply.staysOpen = true
        server.respond("/documento.pdf", reply)
        let probe = FallbackProbe(returning: FetchedLinkPreview(title: "Título da reserva"))

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/documento.pdf"))

        #expect(preview.title == "Título da reserva")
        #expect(probe.urls == [server.url("/documento.pdf")])
        await waitUntil("a transferência do PDF ser interrompida") { server.interruptedPaths.contains("/documento.pdf") }
    }

    // MARK: Endereço

    @Test("Um endereço http é buscado por https, a imagem e o ícone também")
    func httpAddressesAreUpgradedToHTTPS() async throws {
        let server = StubServer()
        server.respond(
            "/artigo",
            html: StubPage.html(image: "http://\(server.host)/capa.png", icons: ["http://\(server.host)/icone.png"]))
        server.respond("/capa.png", image: try TestImage.png(width: 400, height: 210))
        server.respond("/icone.png", image: try TestImage.png(width: 64, height: 64))
        let probe = FallbackProbe()

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/artigo", scheme: "http"))

        #expect(preview.title == "Título da página")
        #expect(preview.imageData != nil && preview.iconData != nil)
        #expect(preview.remoteImageURL == server.url("/capa.png"))
        #expect(server.requestedPaths == ["/artigo", "/capa.png", "/icone.png"])
        #expect(server.requests.allSatisfy { $0.url.scheme == "https" }, "nenhuma requisição saiu por http")
        #expect(probe.urls.isEmpty)
    }

    @Test("Se a página só existe em http, a reserva tenta o endereço original e, sem resultado, a busca falha")
    func httpOnlyPageFallsBackToTheOriginalAddress() async throws {
        let server = StubServer()
        server.respond("/antiga", StubServer.Reply(failure: .cannotConnectToHost))
        let original = server.url("/antiga", scheme: "http")

        let probe = FallbackProbe(returning: FetchedLinkPreview(title: "Título da reserva"))
        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/antiga", scheme: "http"))
        #expect(preview.title == "Título da reserva")
        #expect(probe.urls == [original])

        let emptyProbe = FallbackProbe()
        let error = await #expect(throws: URLError.self) {
            try await makeFetcher(emptyProbe).fetchPreview(for: server.request("/antiga", scheme: "http"))
        }
        #expect(error?.code == .cannotConnectToHost)
        #expect(emptyProbe.urls == [original])
        #expect(server.requests.allSatisfy { $0.url.scheme == "https" }, "nenhuma requisição saiu por http")
    }

    @Test("Um endereço que não é da web é recusado sem requisição")
    func nonWebAddressIsRejected() async {
        let probe = FallbackProbe(returning: FetchedLinkPreview(title: "Título da reserva"))
        let request = LinkPreviewRequest(itemID: UUID(), url: URL(string: "ftp://example.com/arquivo")!)

        await #expect(throws: LinkPreviewFetchError.unsupportedAddress) {
            try await makeFetcher(probe).fetchPreview(for: request)
        }
        #expect(probe.urls.isEmpty)
    }

    // MARK: Imagem

    @Test("A imagem do Safari tem prioridade sobre a og:image")
    func safariImageBeatsOpenGraphImage() async throws {
        let server = StubServer()
        let safari = try TestImage.png(width: 300, height: 200)
        let openGraph = try TestImage.png(width: 400, height: 210)
        server.respond("/artigo", html: StubPage.html(image: "/og.png"))
        server.respond("/safari.png", image: safari)
        server.respond("/og.png", image: openGraph)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo", remoteImage: "/safari.png"))

        #expect(preview.imageData == safari)
        #expect(preview.remoteImageURL == server.url("/safari.png"))
        #expect(!server.requestedPaths.contains("/og.png"), "a og:image nem chegou a ser pedida")
    }

    @Test("Se a imagem do Safari falha, vale a og:image")
    func openGraphImageIsTheFallbackOfTheSafariImage() async throws {
        let server = StubServer()
        let openGraph = try TestImage.png(width: 400, height: 210)
        server.respond("/artigo", html: StubPage.html(image: "/og.png"))
        server.respond("/safari.png", status: 404)
        server.respond("/og.png", image: openGraph)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo", remoteImage: "/safari.png"))

        #expect(preview.imageData == openGraph)
        #expect(preview.remoteImageURL == server.url("/og.png"))
        #expect(server.requestedPaths.prefix(3) == ["/artigo", "/safari.png", "/og.png"])
    }

    @Test("Uma imagem que o ImageIO não lê é ignorada e vale a seguinte")
    func unreadableImageIsSkipped() async throws {
        let server = StubServer()
        let openGraph = try TestImage.png(width: 400, height: 210)
        server.respond("/artigo", html: StubPage.html(image: "/og.png"))
        server.respond("/safari.png", image: Data("não sou uma imagem".utf8))
        server.respond("/og.png", image: openGraph)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo", remoteImage: "/safari.png"))

        #expect(preview.imageData == openGraph)
    }

    @Test("Quando a própria página é uma imagem, ela é a imagem de prévia")
    func imagePageIsItsOwnPreviewImage() async throws {
        let server = StubServer()
        let image = try TestImage.png(width: 400, height: 210)
        server.respond("/foto.png", image: image)
        let probe = FallbackProbe()

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/foto.png"))

        #expect(preview.imageData == image)
        #expect(preview.remoteImageURL == server.url("/foto.png"))
        #expect(preview.title == nil)
        #expect(probe.urls == [server.url("/foto.png")], "sem título a reserva é chamada")
        #expect(server.requestedPaths == ["/foto.png", "/favicon.ico"])
    }

    @Test("Uma imagem do Safari igual à própria página não é baixada duas vezes")
    func safariImageEqualToTheImagePageIsNotDownloadedTwice() async throws {
        let server = StubServer()
        let image = try TestImage.png(width: 400, height: 210)
        server.respond("/foto.png", image: image)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/foto.png", remoteImage: "/foto.png"))

        #expect(preview.imageData == image)
        #expect(server.requestedPaths.filter { $0 == "/foto.png" }.count == 1)
    }

    @Test("Imagem acima de 5 MB é recusada quando o Content-Length já a anuncia")
    func oversizedImageIsRefusedByContentLength() async throws {
        let server = StubServer()
        server.respond("/artigo", html: StubPage.html(image: "/grande.png"))
        // O corpo é um PNG válido e pequeno: se o cabeçalho fosse ignorado, a imagem seria aceita.
        server.respond(
            "/grande.png", image: try TestImage.png(width: 400, height: 210),
            headers: ["Content-Length": String(Self.imageLimit + 1)])

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.imageData == nil)
        #expect(preview.remoteImageURL == nil)
        #expect(preview.title == "Título da página")
    }

    @Test("Imagem acima de 5 MB é recusada também sem Content-Length")
    func oversizedImageIsRefusedWithoutContentLength() async throws {
        let server = StubServer()
        server.respond("/artigo", html: StubPage.html(image: "/grande.png"))
        // PNG válido com zeros até passar 1 byte do limite: sem o corte por tamanho, o ImageIO a leria.
        server.respond("/grande.png", image: try TestImage.png(width: 400, height: 210, paddedTo: Self.imageLimit + 1))

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.imageData == nil)
        #expect(preview.remoteImageURL == nil)
    }

    @Test("Uma imagem de exatamente 5 MB é aceita")
    func imageOfExactlyTheLimitIsAccepted() async throws {
        let server = StubServer()
        let image = try TestImage.png(width: 400, height: 210, paddedTo: Self.imageLimit)
        server.respond("/artigo", html: StubPage.html(image: "/limite.png"))
        server.respond("/limite.png", image: image)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.imageData == image)
    }

    // MARK: Ícone

    @Test("Um ícone que falha cai para o seguinte, e o /favicon.ico fica de fora se um deles servir")
    func failingIconFallsThroughToTheNextOne() async throws {
        let server = StubServer()
        let icon = try TestImage.png(width: 64, height: 64)
        server.respond("/artigo", html: StubPage.html(icons: ["/primeiro.png", "/segundo.png"]))
        server.respond("/primeiro.png", status: 500)
        server.respond("/segundo.png", image: icon)
        server.respond("/favicon.ico", image: try TestImage.png(width: 16, height: 16))

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.iconData == icon)
        #expect(server.requestedPaths == ["/artigo", "/primeiro.png", "/segundo.png"])
    }

    @Test("Se nenhum ícone declarado serve, vale o /favicon.ico da origem")
    func faviconIsTheLastResort() async throws {
        let server = StubServer()
        let favicon = try TestImage.png(width: 32, height: 32)
        server.respond("/artigos/leitura", html: StubPage.html(icons: ["/primeiro.png", "/segundo.png"]))
        server.respond("/primeiro.png", status: 500)
        server.respond("/segundo.png", status: 404)
        server.respond("/favicon.ico", image: favicon, contentType: "image/x-icon")

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigos/leitura"))

        #expect(preview.iconData == favicon)
        #expect(server.requestedPaths == ["/artigos/leitura", "/primeiro.png", "/segundo.png", "/favicon.ico"])
    }

    @Test("Ícone ilegível ou acima de 512 KB é ignorado")
    func unreadableAndOversizedIconsAreIgnored() async throws {
        let server = StubServer()
        let icon = try TestImage.png(width: 64, height: 64)
        server.respond("/artigo", html: StubPage.html(icons: ["/texto.png", "/grande.png", "/limite.png"]))
        server.respond("/texto.png", image: Data("<html>isto não é um ícone</html>".utf8))
        server.respond("/grande.png", image: try TestImage.png(width: 64, height: 64, paddedTo: Self.iconLimit + 1))
        server.respond("/limite.png", image: icon)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.iconData == icon)
        #expect(server.requestedPaths == ["/artigo", "/texto.png", "/grande.png", "/limite.png"])
    }

    @Test("Só os primeiros ícones declarados são tentados, mais o /favicon.ico")
    func declaredIconsAreCapped() async throws {
        let server = StubServer()
        let icons = (1...8).map { "/icone-\($0).png" }
        server.respond("/artigo", html: StubPage.html(icons: icons))

        let preview = try await makeFetcher().fetchPreview(for: server.request("/artigo"))

        #expect(preview.iconData == nil)
        let expected = ["/artigo"] + icons.prefix(SystemLinkPreviewFetcher.maximumDeclaredIcons) + ["/favicon.ico"]
        #expect(server.requestedPaths == expected)
    }

    // MARK: Reserva

    @Test("Com título e sem imagem, a reserva só preenche o que falta")
    func fallbackFillsOnlyWhatIsMissingWhenTheImageIsMissing() async throws {
        let server = StubServer()
        let pageIcon = try TestImage.png(width: 64, height: 64)
        server.respond("/artigo", html: StubPage.html(siteName: nil, icons: ["/icone.png"]))
        server.respond("/icone.png", image: pageIcon)
        let fallbackImage = try TestImage.png(width: 300, height: 200)
        let probe = FallbackProbe(
            returning: FetchedLinkPreview(
                title: "Título da reserva", siteName: "Site da reserva", summary: "Resumo da reserva",
                imageData: fallbackImage, iconData: try TestImage.png(width: 32, height: 32)))

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/artigo"))

        #expect(preview.title == "Título da página", "o título da página vale mais que o da reserva")
        #expect(preview.summary == "Resumo da página")
        #expect(preview.siteName == "Site da reserva", "o que a página não deu vem da reserva")
        #expect(preview.imageData == fallbackImage)
        #expect(preview.iconData == pageIcon, "o ícone da página vale mais que o da reserva")
        #expect(probe.urls == [server.url("/artigo")])
    }

    @Test("Com imagem e sem título, a reserva dá o título e a imagem da página fica")
    func fallbackFillsTheTitleWhenOnlyTheTitleIsMissing() async throws {
        let server = StubServer()
        let pageImage = try TestImage.png(width: 400, height: 210)
        server.respond("/artigo", html: StubPage.html(title: nil, image: "/capa.png"))
        server.respond("/capa.png", image: pageImage)
        let probe = FallbackProbe(
            returning: FetchedLinkPreview(title: "  Título da reserva  ", imageData: try TestImage.png(width: 300, height: 200)))

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/artigo"))

        #expect(preview.title == "Título da reserva")
        #expect(preview.imageData == pageImage)
        #expect(preview.remoteImageURL == server.url("/capa.png"))
        #expect(probe.urls.count == 1)
    }

    @Test("A reserva também completa o ícone quando a página não deu nenhum")
    func fallbackFillsTheIconWhenThePageGivesNone() async throws {
        let server = StubServer()
        server.respond("/artigo", html: StubPage.html(title: nil))
        let fallbackIcon = try TestImage.png(width: 32, height: 32)
        let probe = FallbackProbe(returning: FetchedLinkPreview(title: "Título da reserva", iconData: fallbackIcon))

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/artigo"))

        #expect(preview.iconData == fallbackIcon)
    }

    @Test("A reserva que falha não derruba o que a página deu")
    func failingFallbackKeepsThePageData() async throws {
        let server = StubServer()
        server.respond("/artigo", html: StubPage.html())
        let probe = FallbackProbe(throwing: URLError(.timedOut))

        let preview = try await makeFetcher(probe).fetchPreview(for: server.request("/artigo"))

        #expect(preview.title == "Título da página")
        #expect(probe.urls.count == 1)
    }

    // MARK: Falhas

    @Test("Sem nenhum dado útil a busca falha, mesmo que a reserva traga só o nome do site")
    func nothingUsefulIsAnError() async {
        let server = StubServer()
        server.respond("/vazia", html: "<html><head></head><body></body></html>")

        for probe in [
            FallbackProbe(), FallbackProbe(returning: FetchedLinkPreview()),
            FallbackProbe(returning: FetchedLinkPreview(siteName: "Só o nome")), FallbackProbe(throwing: URLError(.timedOut)),
        ] {
            await #expect(throws: LinkPreviewFetchError.nothingUseful) {
                try await makeFetcher(probe).fetchPreview(for: server.request("/vazia"))
            }
        }
    }

    @Test("Status 404 falha sem pedir imagem nem ícone à origem, e a reserva ainda pode salvar a busca")
    func notFoundFailsUnlessTheFallbackHelps() async throws {
        let server = StubServer()
        let probe = FallbackProbe()

        await #expect(throws: LinkPreviewFetchError.badStatus(404)) {
            try await makeFetcher(probe).fetchPreview(for: server.request("/inexistente"))
        }
        #expect(server.requestedPaths == ["/inexistente"], "nem o /favicon.ico foi pedido")
        #expect(probe.urls == [server.url("/inexistente")])

        let helping = FallbackProbe(returning: FetchedLinkPreview(title: "Título da reserva"))
        let preview = try await makeFetcher(helping).fetchPreview(for: server.request("/inexistente"))
        #expect(preview.title == "Título da reserva")
    }

    @Test("A imagem do Safari ainda vale quando a página falha")
    func safariImageSurvivesAFailingPage() async throws {
        let server = StubServer()
        let safari = try TestImage.png(width: 300, height: 200)
        server.respond("/safari.png", image: safari)

        let preview = try await makeFetcher().fetchPreview(for: server.request("/inexistente", remoteImage: "/safari.png"))

        #expect(preview.imageData == safari)
        #expect(preview.title == nil)
    }

    // MARK: Cancelamento

    @Test("Cancelar durante a página interrompe a transferência e não chama a reserva")
    func cancellationDuringThePage() async {
        let server = StubServer()
        server.respond("/lenta", StubServer.Reply(neverAnswers: true))
        let probe = FallbackProbe(returning: FetchedLinkPreview(title: "Título da reserva"))
        let fetcher = makeFetcher(probe)
        let request = server.request("/lenta")

        let task = Task { try await fetcher.fetchPreview(for: request) }
        await waitUntil("a página ser pedida") { server.requestedPaths == ["/lenta"] }
        task.cancel()

        // A sessão de teste espera 5 s por uma resposta: acabar bem antes prova que o cancelamento interrompeu a transferência.
        let elapsed = await ContinuousClock().measure {
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(elapsed < .seconds(3), "o cancelamento deveria interromper a transferência, não esperar o prazo")
        await waitUntil("a transferência ser interrompida") { server.interruptedPaths == ["/lenta"] }
        #expect(probe.urls.isEmpty)
    }

    @Test("Cancelar durante a imagem não pede ícone nem chama a reserva")
    func cancellationBetweenSteps() async {
        let server = StubServer()
        server.respond("/artigo", html: StubPage.html(image: "/capa.png", icons: ["/icone.png"]))
        server.respond("/capa.png", StubServer.Reply(neverAnswers: true))
        let probe = FallbackProbe(returning: FetchedLinkPreview(title: "Título da reserva"))
        let fetcher = makeFetcher(probe)
        let request = server.request("/artigo")

        let task = Task { try await fetcher.fetchPreview(for: request) }
        await waitUntil("a imagem ser pedida") { server.requestedPaths.contains("/capa.png") }
        task.cancel()

        let elapsed = await ContinuousClock().measure {
            await #expect(throws: CancellationError.self) { try await task.value }
        }
        #expect(elapsed < .seconds(3), "o cancelamento deveria interromper a transferência, não esperar o prazo")
        #expect(server.requestedPaths == ["/artigo", "/capa.png"], "nem o ícone nem o /favicon.ico foram pedidos")
        #expect(probe.urls.isEmpty)
    }

    @Test("Uma tarefa já cancelada não faz requisição")
    func alreadyCancelledTaskMakesNoRequest() async {
        let server = StubServer()
        server.respond("/artigo", html: StubPage.html())
        let fetcher = makeFetcher()
        let request = server.request("/artigo")

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fetcher.fetchPreview(for: request)
        }

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(server.requests.isEmpty)
    }

    // MARK: Configuração

    @Test("A sessão padrão não guarda cookies, credenciais nem cache e tem prazos curtos")
    func defaultConfigurationIsPrivateAndShortLived() {
        let configuration = SystemLinkPreviewFetcher.defaultConfiguration(languages: ["pt-BR", "en-US", "fr"])

        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.urlCredentialStorage == nil)
        #expect(configuration.urlCache == nil)
        #expect(configuration.timeoutIntervalForRequest == 15)
        #expect(configuration.timeoutIntervalForResource == 30)
        #expect(configuration.waitsForConnectivity == false)
        #expect(configuration.httpAdditionalHeaders?["Accept-Language"] as? String == "pt-BR, en-US;q=0.9, fr;q=0.8")
        #expect((configuration.httpAdditionalHeaders?["Accept"] as? String)?.hasPrefix("text/html") == true)
    }

    @Test("Accept-Language lista até 5 idiomas, do mais ao menos preferido, e é omitido sem idiomas")
    func acceptLanguageListsTheUsersLanguages() {
        #expect(SystemLinkPreviewFetcher.acceptLanguage(for: []) == nil)
        #expect(SystemLinkPreviewFetcher.acceptLanguage(for: ["pt-BR"]) == "pt-BR")
        #expect(
            SystemLinkPreviewFetcher.acceptLanguage(for: ["pt-BR", "en", "es", "fr", "de", "it"])
                == "pt-BR, en;q=0.9, es;q=0.8, fr;q=0.7, de;q=0.6")
    }

    // MARK: Apoio

    /// O buscador sobre uma sessão que só fala com os servidores falsos, com prazo curto para um erro não travar o teste.
    private func makeFetcher(_ probe: FallbackProbe = FallbackProbe()) -> SystemLinkPreviewFetcher {
        let configuration = SystemLinkPreviewFetcher.defaultConfiguration(languages: ["pt-BR", "en"])
        configuration.timeoutIntervalForRequest = 5
        return SystemLinkPreviewFetcher(session: StubURLProtocol.session(configuration: configuration), fallback: probe.fallback)
    }
}

/// Reserva de mentira: guarda os endereços recebidos e devolve sempre o mesmo resultado.
private final class FallbackProbe: Sendable {
    private let calls = Mutex<[URL]>([])
    private let result: Result<FetchedLinkPreview?, any Error>

    init(returning preview: FetchedLinkPreview? = nil) {
        result = .success(preview)
    }

    init(throwing error: any Error) {
        result = .failure(error)
    }

    var urls: [URL] { calls.withLock { $0 } }

    var fallback: SystemLinkPreviewFetcher.Fallback {
        { url in
            self.calls.withLock { $0.append(url) }
            return try self.result.get()
        }
    }
}

/// Páginas HTML mínimas para os testes.
private enum StubPage {
    static func html(
        title: String? = "Título da página", description: String? = "Resumo da página", siteName: String? = "Site de teste",
        image: String? = nil, icons: [String] = []
    ) -> String {
        var head = "<meta charset=\"utf-8\">"
        if let title { head += "<meta property=\"og:title\" content=\"\(title)\">" }
        if let description { head += "<meta property=\"og:description\" content=\"\(description)\">" }
        if let siteName { head += "<meta property=\"og:site_name\" content=\"\(siteName)\">" }
        if let image { head += "<meta property=\"og:image\" content=\"\(image)\">" }
        for icon in icons { head += "<link rel=\"icon\" href=\"\(icon)\">" }
        return "<!doctype html><html><head>\(head)</head><body><p>Corpo da página</p></body></html>"
    }
}

extension StubServer {
    /// Pedido de prévia para um caminho deste servidor; `remoteImage` é a imagem que o Safari entregaria.
    fileprivate func request(_ path: String, scheme: String = "https", remoteImage: String? = nil) -> LinkPreviewRequest {
        LinkPreviewRequest(itemID: UUID(), url: url(path, scheme: scheme), remoteImageURL: remoteImage.map { url($0) })
    }
}
