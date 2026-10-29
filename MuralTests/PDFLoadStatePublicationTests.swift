import Testing

@testable import Mural

@Suite("Publicação do estado de carregamento do PDF")
struct PDFLoadStatePublicationTests {
    @Test("Estado terminal não é substituído por uma publicação de progresso atrasada")
    @MainActor
    func terminalStateCannotRevertToLoading() {
        var publication = PDFLoadStatePublication()
        let request = publication.beginRequest()

        let acceptedLoadedState = publication.publish(.loaded, for: request)
        let acceptedDelayedProgress = publication.publish(.loading, for: request)
        let acceptedLateFailure = publication.publish(.failed, for: request)

        #expect(acceptedLoadedState)
        #expect(!acceptedDelayedProgress)
        #expect(!acceptedLateFailure)
    }

    @Test("Publicações antigas e de uma vista desmontada são ignoradas")
    @MainActor
    func staleRequestsAreIgnored() {
        var publication = PDFLoadStatePublication()
        let oldRequest = publication.beginRequest()
        let currentRequest = publication.beginRequest()

        let acceptedOldRequest = publication.publish(.loaded, for: oldRequest)
        let acceptedCurrentProgress = publication.publish(.loading, for: currentRequest)

        publication.invalidate()
        let acceptedInvalidatedRequest = publication.publish(.failed, for: currentRequest)

        #expect(!acceptedOldRequest)
        #expect(acceptedCurrentProgress)
        #expect(!acceptedInvalidatedRequest)
    }
}
