import Foundation
import Testing

@testable import Mural

@Suite("Capacidade da importação de Fotos")
struct PhotoImportCapacityTests {
    @Test("aceita duas cópias mantendo a reserva de segurança")
    func acceptsWithinReservedCapacity() throws {
        _ = try PhotoImportCapacityPolicy.validate(fileSize: 100, availableCapacity: 1_000)
    }

    @Test("recusa quando duas cópias ultrapassam o orçamento disponível")
    func rejectsInsufficientCapacity() {
        do {
            _ = try PhotoImportCapacityPolicy.validate(fileSize: 100, availableCapacity: 100)
            Issue.record("A capacidade insuficiente deveria ser recusada.")
        } catch let error as PhotoImportCapacityError {
            #expect(error == .insufficientCapacity(requiredBytes: 200, availableBytes: 100))
            #expect(PhotoImportCapacityPolicy.message(for: error).contains("espaço livre"))
        } catch {
            Issue.record("Erro inesperado: \(error)")
        }
    }

    @Test("considera a reserva dos arquivos staged anteriores")
    func acceptsCumulativeReservation() throws {
        _ = try PhotoImportCapacityPolicy.validate(
            fileSize: 100,
            availableCapacity: 1_000,
            alreadyReservedBytes: 500)
    }

    @Test("recusa quando a reserva acumulada excede o orçamento")
    func rejectsCumulativeReservation() {
        do {
            _ = try PhotoImportCapacityPolicy.validate(
                fileSize: 100,
                availableCapacity: 1_000,
                alreadyReservedBytes: 700)
            Issue.record("A reserva acumulada deveria ser recusada.")
        } catch let error as PhotoImportCapacityError {
            #expect(error == .insufficientCapacity(requiredBytes: 900, availableBytes: 1_000))
        } catch {
            Issue.record("Erro inesperado: \(error)")
        }
    }

    @Test("trata overflow da reserva acumulada")
    func rejectsCumulativeOverflow() {
        do {
            _ = try PhotoImportCapacityPolicy.validate(
                fileSize: 1,
                availableCapacity: .max,
                alreadyReservedBytes: .max - 1)
            Issue.record("Overflow acumulado deveria ser recusado.")
        } catch let error as PhotoImportCapacityError {
            #expect(error == .arithmeticOverflow)
        } catch {
            Issue.record("Erro inesperado: \(error)")
        }
    }

    @Test("trata overflow do tamanho em bytes")
    func rejectsOverflow() {
        do {
            _ = try PhotoImportCapacityPolicy.validate(fileSize: .max, availableCapacity: .max)
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
            _ = try PhotoImportCapacityPolicy.validate(fileAt: url) { _ in
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

@Suite("Limpeza do staging de Fotos")
struct PhotoImportCleanupTests {
    @Test("remove somente UUIDs antigos e preserva recentes e ativos")
    func sweepsConservatively() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("photo-sweep-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 2_000_000)
        let oldDate = now.addingTimeInterval(-PhotoImportCleanup.maxAge - 1)
        let recentDate = now.addingTimeInterval(-PhotoImportCleanup.maxAge + 1)
        let oldDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let oldFile = root.appendingPathComponent(UUID().uuidString)
        let recentDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let recentFile = root.appendingPathComponent(UUID().uuidString)
        let activeDirectory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let activeFile = root.appendingPathComponent(UUID().uuidString)
        let unrelated = root.appendingPathComponent("not-an-operation")
        try FileManager.default.createDirectory(at: oldDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: recentDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: activeDirectory, withIntermediateDirectories: true)
        for url in [oldFile, recentFile, activeFile, unrelated] { try Data([1]).write(to: url) }
        for url in [oldDirectory, oldFile] {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }
        for url in [recentDirectory, recentFile, unrelated] {
            try FileManager.default.setAttributes([.modificationDate: recentDate], ofItemAtPath: url.path)
        }
        for url in [activeDirectory, activeFile] {
            try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: url.path)
        }
        PhotoImportCleanup.register(activeDirectory)
        PhotoImportCleanup.register(activeFile)

        let removed = PhotoImportCleanup.sweep(roots: [root], now: now)
        PhotoImportCleanup.unregister([activeDirectory, activeFile])

        #expect(Set(removed) == Set([oldDirectory, oldFile]))
        #expect(!FileManager.default.fileExists(atPath: oldDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
        #expect(FileManager.default.fileExists(atPath: recentDirectory.path))
        #expect(FileManager.default.fileExists(atPath: recentFile.path))
        #expect(FileManager.default.fileExists(atPath: activeDirectory.path))
        #expect(FileManager.default.fileExists(atPath: activeFile.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
