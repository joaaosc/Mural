import MuralKit
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

    @Test("Esmaecimento alcança todo o conteúdo que ultrapassa o quadro do cartão", arguments: [ColorScheme.light, .dark])
    func dimsContentOutsideLayoutBounds(scheme: ColorScheme) throws {
        let content = Color.gray
            .frame(width: 40, height: 40)
            .overlay { Color.gray.frame(width: 140, height: 600) }
            .cardEmphasis(0.3)
            .frame(width: 200, height: 700)
            .environment(\.colorScheme, scheme)
        let center = try RenderedPixel.read(content, size: CGSize(width: 200, height: 700), at: CGPoint(x: 100, y: 350))
        for point in [CGPoint(x: 160, y: 350), CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 600)] {
            let overflow = try RenderedPixel.read(content, size: CGSize(width: 200, height: 700), at: point)
            #expect(abs(overflow.red - center.red) < 0.02, "esmaecimento desigual em \(point): \(overflow), centro \(center)")
            #expect(abs(overflow.green - center.green) < 0.02)
            #expect(abs(overflow.blue - center.blue) < 0.02)
            #expect(overflow.alpha == 1)
        }
    }

    @Test("Esmaecimento mantém transparentes os espaços vazios em volta do cartão")
    func dimmingDoesNotPaintOutsideContent() throws {
        let pixel = try RenderedPixel.read(
            Circle().fill(.gray).frame(width: 40, height: 40).cardEmphasis(0.3).padding(30),
            size: CGSize(width: 100, height: 100), at: CGPoint(x: 10, y: 10))
        #expect(pixel.alpha == 0)
    }

    @Test("O leque e a folha da pasta recebem o mesmo esmaecimento", arguments: [ColorScheme.light, .dark])
    func dimsTheEntireFolderFan(scheme: ColorScheme) throws {
        let peeks = (0..<3).map { index in
            FolderPeekItem(id: UUID(), kind: .sticky, title: "Nota \(index)", fileURL: nil, stickyColor: .pink)
        }
        let folder = FolderCard(folder: BoardItem(kind: .folder, title: "Pasta"), itemCount: 3, peeks: peeks)
            .frame(width: 150, height: 190)
            .cardEmphasis(0)
            .padding(80)
            .environment(\.colorScheme, scheme)
        let expected = try Self.centerPixel(Theme.canvas.environment(\.colorScheme, scheme))
        for point in [CGPoint(x: 155, y: 175), CGPoint(x: 260, y: 175)] {
            let pixel = try RenderedPixel.read(folder, size: CGSize(width: 310, height: 350), at: point)
            #expect(abs(pixel.red - expected.red) < 0.02, "folha ou leque fora do efeito em \(point): \(pixel)")
            #expect(abs(pixel.green - expected.green) < 0.02)
            #expect(abs(pixel.blue - expected.blue) < 0.02)
            #expect(pixel.alpha == 1)
        }
    }

    private static func centerPixel(_ content: some View) throws -> RenderedPixel {
        try RenderedPixel.read(content, size: CGSize(width: 40, height: 40), at: CGPoint(x: 20, y: 20))
    }
}
