import Foundation
import Testing

@testable import Mural

@Suite("Capacidade da importação de Fotos")
struct PhotoImportCapacityTests {
    @Test("aceita duas cópias mantendo a reserva de segurança")
    func acceptsWithinReservedCapacity() throws {
        try PhotoImportCapacityPolicy.validate(fileSize: 100, availableCapacity: 1_000)
    }

    @Test("recusa quando duas cópias ultrapassam o orçamento disponível")
    func rejectsInsufficientCapacity() {
        do {
            try PhotoImportCapacityPolicy.validate(fileSize: 100, availableCapacity: 100)
            Issue.record("A capacidade insuficiente deveria ser recusada.")
        } catch let error as PhotoImportCapacityError {
            #expect(error == .insufficientCapacity(requiredBytes: 200, availableBytes: 100))
            #expect(PhotoImportCapacityPolicy.message(for: error).contains("espaço livre"))
        } catch {
            Issue.record("Erro inesperado: \(error)")
        }
    }

    @Test("trata overflow do tamanho em bytes")
    func rejectsOverflow() {
        do {
            try PhotoImportCapacityPolicy.validate(fileSize: .max, availableCapacity: .max)
            Issue.record("Overflow deveria ser recusado.")
        } catch let error as PhotoImportCapacityError {
            #expect(error == .arithmeticOverflow)
        } catch {
            Issue.record("Erro inesperado: \(error)")
        }
    }

    @Test("capacidade indisponível não é tratada como infinita")
    func rejectsUnavailableCapacity() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-capacity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([1]).write(to: url)

        do {
            try PhotoImportCapacityPolicy.validate(fileAt: url) { _ in
                (fileSize: 1, availableCapacity: nil)
            }
            Issue.record("Capacidade ausente deveria ser recusada.")
        } catch let error as PhotoImportCapacityError {
            #expect(error == .capacityUnavailable)
            #expect(PhotoImportCapacityPolicy.message(for: error).contains("verificar"))
        } catch {
            Issue.record("Erro inesperado: \(error)")
        }
    }
}
