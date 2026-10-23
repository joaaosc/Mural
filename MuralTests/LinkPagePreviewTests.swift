import AppKit
import CoreGraphics
import ImageIO
import MuralKit
import SwiftUI
import Testing
import WebKit

@testable import Mural

/// "Usar como prévia" de ponta a ponta, com uma `WebPage` de verdade e HTML local (sem rede): a página é carregada
/// pelo mesmo `LinkNavigationDecider` do app, capturada pelo mesmo código e gravada no cartão.
///
/// A página fica numa janela do app, atrás das outras: o WebKit só tem tamanho de área visível (e portanto recorte)
/// dentro de uma janela.
@Suite(.serialized)
@MainActor
struct LinkPagePreviewTests {
    /// Tamanho da área da página nestes testes.
    private static let viewport = CGSize(width: 800, height: 600)
    private static let pageURL = URL(string: "https://example.com/faixas")!
    private static let red = RenderedPixel(red: 220.0 / 255, green: 30.0 / 255, blue: 30.0 / 255, alpha: 1)
    private static let green = RenderedPixel(red: 30.0 / 255, green: 170.0 / 255, blue: 60.0 / 255, alpha: 1)

    /// Três faixas de 1.200 pontos, vermelha, verde e azul, uma depois da outra: a cor no topo da área visível diz
    /// até onde a página rolou.
    private static let bandsHTML = """
        <!doctype html>
        <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
        <style>
          html, body { margin: 0; }
          div { height: 1200px; }
          #a { background: rgb(220, 30, 30); }
          #b { background: rgb(30, 170, 60); }
          #c { background: rgb(40, 70, 220); }
        </style></head>
        <body><div id="a"></div><div id="b"></div><div id="c"></div></body></html>
        """

    @Test("A captura segue a proporção da prévia e mostra o topo da área visível")
    func captureHasThePreviewAspectAndShowsTheTop() async throws {
        let (controller, window) = try await makeLoadedPage()
        defer { close(controller, window) }
        let page = try #require(controller.page)

        let image = try await capture(page)

        #expect(abs(Double(image.width) / Double(image.height) - LinkCard.imageAspectRatio) < 0.03, "\(image.width) × \(image.height)")
        #expect(image.width >= 800, "\(image.width) × \(image.height)")
        let pixel = try RenderedPixel.read(image, fractionX: 0.5, fractionY: 0.1)
        #expect(pixel.isNear(Self.red), "o topo da página é vermelho: \(pixel)")
    }

    @Test("Com a página rolada, a captura mostra o que está à vista e não o começo da página")
    func captureFollowsTheScroll() async throws {
        let (controller, window) = try await makeLoadedPage()
        defer { close(controller, window) }
        let page = try #require(controller.page)

        // A faixa verde vai de 1.200 a 2.400: com a página rolada a 1.500, o topo da área visível é verde.
        let scrollY = try await page.callJavaScript("window.scrollTo(0, 1500); return window.scrollY") as? NSNumber
        try #require(scrollY?.doubleValue == 1_500, "a página não rolou: \(String(describing: scrollY))")
        let image = try await capture(page)

        let pixel = try RenderedPixel.read(image, fractionX: 0.5, fractionY: 0.1)
        #expect(pixel.isNear(Self.green), "o recorte saiu do lugar com a página rolada: \(pixel)")
    }

    @Test("Usar como prévia grava a imagem da página e o cartão passa a usá-la")
    func usingThePageAsPreviewUpdatesTheCard() async throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = try #require(fixture.model.importLinks([LinkDraft(url: Self.pageURL, title: "Faixas")]).first)
        let files = LinkPreviewFiles(directory: fixture.directory.appendingPathComponent("LinkPreviews", isDirectory: true))
        let (controller, window) = try await makeLoadedPage()
        defer { close(controller, window) }

        controller.usePageAsPreview(itemID: item.id, in: fixture.model, files: files)
        await waitUntil("a prévia ser gravada") { controller.previewState == .saved || fixture.model.lastError != nil }

        #expect(fixture.model.lastError == nil)
        #expect(controller.previewState == .saved)
        let stored = fixture.model.item(id: item.id)
        let name = try #require(stored?.link?.previewImageFile, "o cartão não recebeu o arquivo da prévia")
        #expect(stored?.link?.preview != .pending)
        let url = try #require(files.url(for: name))
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "o arquivo da prévia não é uma imagem")
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width <= 800 && image.width >= 400, "\(image.width) × \(image.height)")
        #expect(abs(Double(image.width) / Double(image.height) - LinkCard.imageAspectRatio) < 0.03)
        let pixel = try RenderedPixel.read(image, fractionX: 0.5, fractionY: 0.1)
        #expect(pixel.isNear(Self.red), "\(pixel)")
    }

    @Test("Se a captura falhar, o cartão fica como estava e o aviso aparece")
    func failedCaptureLeavesTheCardAlone() throws {
        let fixture = LinkImportFixture()
        defer { fixture.tearDown() }
        let item = try #require(fixture.model.importLinks([LinkDraft(url: Self.pageURL, title: "Faixas")]).first)
        let files = LinkPreviewFiles(directory: fixture.directory.appendingPathComponent("LinkPreviews", isDirectory: true))
        let controller = LinkPageController()
        controller.start(url: Self.pageURL, source: .html(Self.bandsHTML))
        defer { controller.stop() }
        // Sem tamanho de área visível não há o que capturar.
        controller.viewportSize = .zero

        controller.usePageAsPreview(itemID: item.id, in: fixture.model, files: files)

        #expect(fixture.model.lastError != nil)
        #expect(fixture.model.item(id: item.id)?.link?.previewImageFile == nil)
        #expect(controller.previewState == .idle)
    }

    // MARK: Apoio

    /// Controlador com a página de faixas carregada numa janela de `viewport`, já com o tamanho da área visível.
    private func makeLoadedPage() async throws -> (LinkPageController, NSWindow) {
        let controller = LinkPageController()
        controller.start(url: Self.pageURL, source: .html(Self.bandsHTML))
        let page = try #require(controller.page)

        let host = NSHostingView(rootView: WebView(page).frame(width: Self.viewport.width, height: Self.viewport.height))
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.viewport), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        controller.viewportSize = Self.viewport

        // Pronta quando o HTML terminou de carregar e a janela deu a largura à página.
        await waitUntil("a página de faixas carregar e ocupar a janela") {
            let width = try? await page.callJavaScript("return document.readyState === 'complete' ? window.innerWidth : 0") as? NSNumber
            return width?.doubleValue == Self.viewport.width
        }
        #expect(controller.failure == nil, "a página falhou: \(String(describing: controller.failure))")
        return (controller, window)
    }

    private func close(_ controller: LinkPageController, _ window: NSWindow) {
        controller.stop()
        window.close()
    }

    /// Captura como o app faz: a região de `LinkPreviewCrop` sobre a área visível, com largura de 800 pontos.
    private func capture(_ page: WebPage) async throws -> CGImage {
        let region = try #require(LinkPreviewCrop.region(inViewportOf: Self.viewport, aspectRatio: LinkCard.imageAspectRatio))
        let data = try await page.exported(as: .image(region: .rect(region), snapshotWidth: 800))
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil), "a captura não é uma imagem")
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }
}

extension RenderedPixel {
    /// Cor de um pixel de uma imagem, numa posição dada em fração da largura e da altura (0 a 1, do canto de cima).
    fileprivate static func read(_ image: CGImage, fractionX: Double, fractionY: Double) throws -> RenderedPixel {
        let column = Int(Double(image.width - 1) * fractionX)
        let row = Int(Double(image.height - 1) * fractionY)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            // O CGContext conta de baixo para cima: a imagem é deslocada para o pixel pedido cair em (0, 0).
            let height = CGFloat(image.height)
            context.draw(image, in: CGRect(x: CGFloat(-column), y: CGFloat(row) + 1 - height, width: CGFloat(image.width), height: height))
            return true
        }
        try #require(drawn)
        return RenderedPixel(
            red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255, blue: Double(bytes[2]) / 255,
            alpha: Double(bytes[3]) / 255)
    }

    /// Opaco e a menos de `tolerance` de `other` em cada canal.
    fileprivate func isNear(_ other: RenderedPixel, tolerance: Double = 0.06) -> Bool {
        alpha > 0.99 && abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance
    }
}
