import Foundation
import Testing

@testable import Mural

@Suite("Diagnóstico da importação de Fotos")
struct PhotoImportDiagnosticsTests {
    private func photosError() -> NSError {
        let underlying = NSError(domain: "PHPhotosErrorDomain", code: -1)
        return NSError(
            domain: NSCocoaErrorDomain, code: 4101,
            userInfo: [NSUnderlyingErrorKey: underlying])
    }

    @Test("erro do Fotos (PHPhotosErrorDomain) vira falha de entrega do Fotos")
    func classifiesPhotosError() {
        #expect(PhotoImportDiagnostics.reason(for: photosError()) == .photosUnavailable)
    }

    @Test("falha do NSItemProvider vira falha de entrega do Fotos")
    func classifiesItemProviderError() {
        let error = NSError(domain: NSItemProvider.errorDomain, code: -1000)
        #expect(PhotoImportDiagnostics.reason(for: error) == .photosUnavailable)
    }

    @Test("erro de representação do CoreTransferable vira falha de formato")
    func classifiesTransferableSupportError() {
        let error = NSError(domain: "CoreTransferable.TransferableSupportError<Mural.PhotoPickerFile>", code: 0)
        #expect(PhotoImportDiagnostics.reason(for: error) == .noRepresentation)
        #expect(PhotoImportDiagnostics.label(forItemAt: 0, reason: .noRepresentation).contains("neste formato"))
    }

    @Test("falta de espaço vence os demais motivos, mesmo aninhada")
    func classifiesOutOfSpace() {
        let direct = CocoaError(.fileWriteOutOfSpace)
        #expect(PhotoImportDiagnostics.reason(for: direct) == .outOfSpace)

        let posix = NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
        let wrapped = NSError(
            domain: "PHPhotosErrorDomain", code: -1,
            userInfo: [NSUnderlyingErrorKey: posix])
        #expect(PhotoImportDiagnostics.reason(for: wrapped) == .outOfSpace)
    }

    @Test("erro desconhecido mantém só a posição do item")
    func unknownErrorKeepsPlainLabel() {
        let reason = PhotoImportDiagnostics.reason(for: CocoaError(.fileReadCorruptFile))
        #expect(reason == .other)
        #expect(PhotoImportDiagnostics.label(forItemAt: 0, reason: reason) == "Item 1")
    }

    @Test("todo texto começa com a posição do item")
    func labelsKeepItemPosition() {
        let reasons: [PhotoImportDiagnostics.Reason] = [
            .unsupportedType, .noRepresentation, .photosUnavailable, .outOfSpace, .other,
        ]
        for reason in reasons {
            #expect(PhotoImportDiagnostics.label(forItemAt: 2, reason: reason).hasPrefix("Item 3"))
        }
    }

    @Test("a cadeia de erros é limitada e descrita de fora para dentro")
    func describesChain() {
        #expect(PhotoImportDiagnostics.describe(photosError()) == "NSCocoaErrorDomain 4101 <- PHPhotosErrorDomain -1")
    }
}
