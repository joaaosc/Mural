import SwiftUI
import Testing

@testable import Mural

/// Esmaecer um cartão não pode deixar ver o que está atrás dele.
@MainActor
struct CardEmphasisTests {
    @Test("Cartão esmaecido esconde o cartão que está atrás dele")
    func dimmedCardHidesCardBehind() throws {
        let pixel = try Self.centerPixel(
            ZStack {
                Color.red
                Color.gray.cardEmphasis(0.3)
            })
        #expect(pixel.isNeutral, "o vermelho de trás atravessou o cartão: \(pixel)")
    }

    @Test("Pasta esmaecida esconde a mídia guardada atrás da própria folha")
    func dimmedFolderHidesItsOwnMedia() throws {
        let pixel = try Self.centerPixel(
            ZStack {
                Color.red
                Color.gray
            }
            .cardEmphasis(0.3))
        #expect(pixel.isNeutral, "a mídia de trás atravessou a folha: \(pixel)")
    }

    @Test("Controle: a opacidade comum deixaria o cartão de trás aparecer")
    func plainOpacityLetsCardBehindShow() throws {
        let pixel = try Self.centerPixel(
            ZStack {
                Color.red
                Color.gray.opacity(0.3)
            })
        #expect(!pixel.isNeutral, "a leitura do pixel deveria notar o vermelho: \(pixel)")
    }

    @Test("Destaque total deixa o cartão como está")
    func fullEmphasisKeepsCard() throws {
        let pixel = try Self.centerPixel(Color(red: 0.2, green: 0.4, blue: 0.6).cardEmphasis(1))
        #expect(abs(pixel.red - 0.2) < 0.02)
        #expect(abs(pixel.green - 0.4) < 0.02)
        #expect(abs(pixel.blue - 0.6) < 0.02)
        #expect(pixel.alpha == 1)
    }

    private static func centerPixel(_ content: some View) throws -> RenderedPixel {
        try RenderedPixel.read(content, size: CGSize(width: 40, height: 40), at: CGPoint(x: 20, y: 20))
    }
}
