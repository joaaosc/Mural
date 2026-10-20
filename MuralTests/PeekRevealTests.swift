import SwiftUI
import Testing

@testable import Mural

/// A prévia de pasta entra revelada da borda da pasta para fora (shader Metal).
@MainActor
struct PeekRevealTests {
    @Test("No meio da entrada, a prévia já aparece junto à pasta e ainda não na ponta")
    func halfwayShowsOnlyTheSideNearTheFolder() throws {
        let reveal = Color.white.modifier(PeekRevealEffect(progress: 0.5))
        #expect(try Self.alpha(of: reveal, atX: 10) > 0.95)
        #expect(try Self.alpha(of: reveal, atX: 190) < 0.05)
    }

    @Test("Antes da entrada nada aparece; no fim, tudo aparece sem filtro")
    func revealStartsHiddenAndEndsWhole() throws {
        #expect(try Self.alpha(of: Color.white.modifier(PeekRevealEffect(progress: 0)), atX: 10) < 0.05)
        #expect(try Self.alpha(of: Color.white.modifier(PeekRevealEffect(progress: 1)), atX: 190) > 0.95)
    }

    /// Alfa de um pixel de uma faixa de 200 × 20 pontos, na altura do meio.
    private static func alpha(of content: some View, atX x: CGFloat) throws -> Double {
        try RenderedPixel.read(content, size: CGSize(width: 200, height: 20), at: CGPoint(x: x, y: 10)).alpha
    }
}
