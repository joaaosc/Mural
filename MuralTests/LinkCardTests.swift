import CoreGraphics
import Foundation
import ImageIO
import MuralKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Mural

/// Desenha o cartão de link fora da tela e lê pixels: confere o que se vê, não a estrutura das views.
@MainActor
struct LinkCardTests {
    /// Tamanho do cartão no mural.
    private static let size = CGSize(width: 150, height: 170)
    /// Dois pontos da área da imagem longe do centro, onde fica a letra do monograma.
    private static let topLeft = CGPoint(x: 20, y: 20)
    private static let topRight = CGPoint(x: 130, y: 60)
    private static let imageColor = RenderedPixel(red: 0.10, green: 0.35, blue: 0.85, alpha: 1)
    private static let iconColor = RenderedPixel(red: 0.85, green: 0.20, blue: 0.15, alpha: 1)

    @Test("Sem imagem de prévia, o topo do cartão tem a cor do monograma do host")
    func topHasMonogramColorWithoutImage() throws {
        let item = Self.linkItem("https://www.Apple.com/br/mac")
        let expected = Self.monogramColor(host: "apple.com")

        for point in [Self.topLeft, Self.topRight] {
            let pixel = try RenderedPixel.read(LinkCard(item: item), size: Self.size, at: point)
            #expect(pixel.isClose(to: expected), "em \(point): \(pixel); esperado \(expected)")
        }
    }

    @Test("Controle: outro host dá outra cor, então a comparação do monograma distingue os sites")
    func differentHostHasDifferentMonogramColor() throws {
        let pixel = try RenderedPixel.read(
            LinkCard(item: Self.linkItem("https://github.com/apple/swift")), size: Self.size, at: Self.topLeft)
        #expect(!pixel.isClose(to: Self.monogramColor(host: "apple.com")), "a cor de github.com é a de apple.com: \(pixel)")
        #expect(pixel.isClose(to: Self.monogramColor(host: "github.com")), "\(pixel)")
    }

    @Test("A área de cima tem a proporção 1,91 da largura e o resto do cartão é papel")
    func coverKeepsItsAspectRatio() throws {
        let item = Self.linkItem("https://apple.com")
        let expected = Self.monogramColor(host: "apple.com")
        // 150 / 1,91 = 78,5: a linha 77 é da área de cima e a 80, já do papel (neutro, em qualquer aparência).
        let inside = try RenderedPixel.read(LinkCard(item: item), size: Self.size, at: CGPoint(x: 146, y: 77))
        let below = try RenderedPixel.read(LinkCard(item: item), size: Self.size, at: CGPoint(x: 146, y: 80))
        #expect(inside.isClose(to: expected), "a área de cima acabou antes de 77: \(inside)")
        #expect(below.isNeutral && below.alpha == 1, "a área de cima passou de 80: \(below)")
    }

    @Test("A sombra é só do papel: logo abaixo da imagem o papel continua branco, sem a sombra da imagem")
    func imageShadowDoesNotFallOnThePaper() throws {
        let card = LinkCard(item: Self.linkItem("https://apple.com")).environment(\.colorScheme, .light)
        // A área de cima acaba em 78,5 e o texto só começa em 86,5: a linha 82 é papel puro.
        let pixel = try RenderedPixel.read(card, size: Self.size, at: CGPoint(x: 75, y: 82))
        #expect(pixel.red > 0.99 && pixel.green > 0.99 && pixel.blue > 0.99, "a imagem projetou sombra no papel: \(pixel)")
    }

    @Test("Com imagem de prévia, o topo mostra a imagem recortada na área e o ícone fica junto do nome do site")
    func topShowsPreviewImageAndIcon() async throws {
        let files = Self.makeFiles()
        defer { try? FileManager.default.removeItem(at: files.directory) }
        // Imagem em pé: ao preencher uma área larga ela passa da área e precisa ser recortada.
        let names = try files.store(
            imageData: Self.solidPNG(width: 200, height: 400, color: Self.imageColor),
            iconData: Self.solidPNG(width: 64, height: 64, color: Self.iconColor),
            for: UUID())
        let image = try #require(names.image)
        let icon = try #require(names.icon)
        let item = Self.linkItem("https://apple.com", previewImageFile: image, iconFile: icon)
        // A miniatura carrega de forma assíncrona e o `ImageRenderer` desenha uma vez só. Com o cache já
        // aquecido, a primeira passada do `ThumbnailView` encontra a imagem pronta, sem espera.
        try await Self.warmCache(files.url(for: image), maxPixelSize: LinkCard.imageMaxPixelSize)
        try await Self.warmCache(files.url(for: icon), maxPixelSize: LinkCard.iconMaxPixelSize)
        let card = LinkCard(item: item).environment(\.linkPreviewFiles, files)

        for point in [Self.topLeft, Self.topRight, CGPoint(x: 146, y: 77)] {
            let pixel = try RenderedPixel.read(card, size: Self.size, at: point)
            #expect(pixel.isClose(to: Self.imageColor), "em \(point): \(pixel); esperado \(Self.imageColor)")
        }
        let below = try RenderedPixel.read(card, size: Self.size, at: CGPoint(x: 146, y: 80))
        #expect(below.isNeutral, "a imagem passou da área de cima: \(below)")
        let iconPixel = try RenderedPixel.read(card, size: Self.size, at: CGPoint(x: 13, y: 91))
        #expect(iconPixel.isClose(to: Self.iconColor), "o ícone não está no começo da linha do site: \(iconPixel)")
    }

    @Test("Sem a pasta de prévias no ambiente, o nome do arquivo sozinho não mostra imagem: fica o monograma")
    func missingEnvironmentFallsBackToMonogram() throws {
        let item = Self.linkItem("https://apple.com", previewImageFile: "inexistente.jpg", iconFile: "inexistente.png")
        let pixel = try RenderedPixel.read(LinkCard(item: item), size: Self.size, at: Self.topLeft)
        #expect(pixel.isClose(to: Self.monogramColor(host: "apple.com")), "\(pixel)")
    }

    // MARK: Apoio

    private static func linkItem(_ address: String, previewImageFile: String? = nil, iconFile: String? = nil) -> BoardItem {
        let url = URL(string: address)!
        return BoardItem(
            kind: .link, title: "Título do link",
            link: LinkInfo(url: url, summary: "Resumo da página", previewImageFile: previewImageFile, iconFile: iconFile))
    }

    private static func makeFiles() -> LinkPreviewFiles {
        LinkPreviewFiles(
            directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                "MuralTests-LinkCard-\(UUID().uuidString)", isDirectory: true))
    }

    private static func warmCache(_ url: URL, maxPixelSize: Int) async throws {
        let request = ThumbnailRequest(url: url, kind: .image, maxPixelSize: maxPixelSize)
        try #require(await ThumbnailCache.shared.image(for: request) != nil, "a miniatura de teste não carregou")
    }

    /// Cor de `Color(hue:saturation:brightness:)` do monograma, calculada à mão no modelo HSB padrão.
    private static func monogramColor(host: String) -> RenderedPixel {
        let hue = LinkMonogram.hue(for: host) * 6
        let saturation = 0.35
        let brightness = 0.82
        let fraction = hue - hue.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        let (red, green, blue) =
            switch Int(hue) {
            case 0: (brightness, rising, low)
            case 1: (falling, brightness, low)
            case 2: (low, brightness, rising)
            case 3: (low, falling, brightness)
            case 4: (rising, low, brightness)
            default: (brightness, low, falling)
            }
        return RenderedPixel(red: red, green: green, blue: blue, alpha: 1)
    }

    private static func solidPNG(width: Int, height: Int, color: RenderedPixel) throws -> Data {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: color.red, green: color.green, blue: color.blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

extension RenderedPixel {
    /// Opaco e a menos de `tolerance` de `other` em cada canal (cores gravadas em 8 bits e, às vezes, em JPEG).
    fileprivate func isClose(to other: RenderedPixel, tolerance: Double = 0.03) -> Bool {
        alpha > 0.99 && abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
            && abs(blue - other.blue) <= tolerance
    }
}
