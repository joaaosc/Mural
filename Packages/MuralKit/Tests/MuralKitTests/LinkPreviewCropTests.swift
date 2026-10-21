import CoreGraphics
import Testing

@testable import MuralKit

@Suite("Recorte da prévia do link")
struct LinkPreviewCropTests {
    private let ratio: CGFloat = 1.91

    @Test("Numa área larga e alta, o recorte tem a largura toda, começa no topo e segue a proporção")
    func fullWidthFromTheTop() throws {
        let region = try #require(LinkPreviewCrop.region(inViewportOf: CGSize(width: 1_000, height: 800), aspectRatio: ratio))

        #expect(region.minX == 0)
        #expect(region.minY == 0)
        #expect(region.width == 1_000)
        #expect(abs(region.width / region.height - ratio) < 0.0001)
    }

    @Test("Numa área estreita, o recorte continua com a largura toda e fica mais baixo que a área")
    func narrowAreaKeepsFullWidth() throws {
        let region = try #require(LinkPreviewCrop.region(inViewportOf: CGSize(width: 382, height: 600), aspectRatio: ratio))

        #expect(region.width == 382)
        #expect(abs(region.height - 200) < 0.0001)
        #expect(region.height < 600)
    }

    @Test("Numa área exatamente na proporção, o recorte é a área toda")
    func exactRatioIsTheWholeArea() throws {
        let region = try #require(LinkPreviewCrop.region(inViewportOf: CGSize(width: 191, height: 100), aspectRatio: ratio))

        #expect(abs(region.minX) < 0.0001)
        #expect(region.minY == 0)
        #expect(abs(region.width - 191) < 0.0001)
        #expect(abs(region.height - 100) < 0.0001)
    }

    @Test("Numa área baixa demais, usa a altura toda e centraliza o recorte na horizontal")
    func shortAreaUsesFullHeightAndCenters() throws {
        let region = try #require(LinkPreviewCrop.region(inViewportOf: CGSize(width: 1_000, height: 200), aspectRatio: ratio))

        #expect(region.minY == 0)
        #expect(region.height == 200)
        #expect(abs(region.width - 382) < 0.0001)
        #expect(abs(region.minX - (1_000 - 382) / 2) < 0.0001)
        #expect(abs(region.width / region.height - ratio) < 0.0001)
    }

    @Test("O recorte nunca sai da área visível")
    func regionStaysInsideTheArea() throws {
        let sizes = [(1_000, 800), (300, 900), (1_200, 100), (640, 335), (5, 5), (1, 1_000)].map {
            CGSize(width: $0.0, height: $0.1)
        }
        for size in sizes {
            let region = try #require(LinkPreviewCrop.region(inViewportOf: size, aspectRatio: ratio))
            let area = CGRect(origin: .zero, size: size)
            #expect(area.insetBy(dx: -0.0001, dy: -0.0001).contains(region), "\(size): \(region)")
        }
    }

    @Test("Área vazia ou inválida não tem recorte")
    func invalidAreaHasNoRegion() {
        let invalid: [CGSize] = [
            .zero, CGSize(width: 0, height: 500), CGSize(width: 500, height: 0), CGSize(width: -10, height: 500),
            CGSize(width: 500, height: -10), CGSize(width: CGFloat.nan, height: 500), CGSize(width: 500, height: CGFloat.infinity),
        ]
        for size in invalid {
            #expect(LinkPreviewCrop.region(inViewportOf: size, aspectRatio: ratio) == nil, "\(size)")
        }
    }

    @Test("Proporção que não é um número positivo não tem recorte")
    func invalidRatioHasNoRegion() {
        for value in [0, -1.91, CGFloat.nan, CGFloat.infinity] {
            #expect(LinkPreviewCrop.region(inViewportOf: CGSize(width: 1_000, height: 800), aspectRatio: value) == nil, "\(value)")
        }
    }
}
