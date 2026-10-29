import CoreGraphics
import MuralKit
import Testing

@testable import Mural

/// Qual canto um ponto alcança para redimensionar, e quando só existe o canto da alça.
@Suite("Cantos de redimensionar")
@MainActor
struct ResizeCornerHitTests {
    private let size = CGSize(width: 150, height: 190)

    @Test("Em zoom 1, cada um dos quatro cantos é um quadrado de 18 pontos")
    func fourCornersAtDefaultZoom() {
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 4, y: 4), size: size, zoom: 1) == .topLeading)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 146, y: 4), size: size, zoom: 1) == .topTrailing)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 4, y: 186), size: size, zoom: 1) == .bottomLeading)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 146, y: 186), size: size, zoom: 1) == .bottomTrailing)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 18, y: 18), size: size, zoom: 1) == .topLeading, "a borda do quadrado conta")
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 19, y: 19), size: size, zoom: 1) == nil)
    }

    @Test("No meio e nas bordas fora dos cantos o arrasto só move")
    func middleAndEdgesMove() {
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 75, y: 95), size: size, zoom: 1) == nil)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 75, y: 4), size: size, zoom: 1) == nil)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 4, y: 95), size: size, zoom: 1) == nil)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: -1, y: 4), size: size, zoom: 1) == nil, "fora do elemento")
    }

    @Test("O quadrado tem o mesmo tamanho na tela em qualquer zoom")
    func squareScalesWithZoom() {
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 14, y: 14), size: size, zoom: 1.25) == .topLeading)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 15, y: 15), size: size, zoom: 1.25) == nil)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 144, y: 188), size: size, zoom: 0.75) == .bottomTrailing)
    }

    @Test("Elemento pequeno na tela só aceita o canto de baixo à direita")
    func smallElementKeepsOnlyBottomTrailing() {
        let small = CGSize(width: 110, height: 110)
        // 110 × 0,5 = 55 pontos de tela, menos que 4 × 18.
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 4, y: 4), size: small, zoom: 0.5) == nil)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 106, y: 4), size: small, zoom: 0.5) == nil)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 4, y: 106), size: small, zoom: 0.5) == nil)
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 106, y: 106), size: small, zoom: 0.5) == .bottomTrailing)
        // O quadrado nunca passa de metade do menor lado: 18 / 0,5 = 36 pontos do mural, e metade de 110 é 55.
        #expect(ResizeCornerHit.corner(at: CGPoint(x: 110 - 36, y: 110 - 36), size: small, zoom: 0.5) == .bottomTrailing)
    }

    @Test("Medidas inválidas não alcançam canto nenhum")
    func invalidInput() {
        #expect(ResizeCornerHit.corner(at: .zero, size: .zero, zoom: 1) == nil)
        #expect(ResizeCornerHit.corner(at: .zero, size: size, zoom: 0) == nil)
    }
}
