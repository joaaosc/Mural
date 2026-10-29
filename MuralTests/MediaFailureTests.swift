import Testing

@testable import Mural

@Suite("Falhas de carregamento de mídia")
@MainActor
struct MediaFailureTests {
    @Test("Miniatura diferencia falha de carregamento de progresso")
    func thumbnailFailureIsExplicit() {
        #expect(ThumbnailLoadPhase.result(hasImage: false) == .failed)
        #expect(ThumbnailLoadPhase.result(hasImage: true) == .loaded)
        #expect(ThumbnailLoadPhase.loading != .failed)
    }

    @Test("PDF sem documento válido termina em estado de falha")
    func invalidPDFIsFailure() {
        #expect(PDFLoadState.result(isValidDocument: false) == .failed)
        #expect(PDFLoadState.result(isValidDocument: true) == .loaded)
    }
}
