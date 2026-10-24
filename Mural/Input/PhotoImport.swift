import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// File-backed representation used by PhotosPicker. The picker supplies a
/// temporary URL; the session copies it into its own staging directory before
/// handing it to the domain importer.
struct PhotoPickerFile: Transferable, Sendable {
    let fileURL: URL

    nonisolated static let transferRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("MuralPhotoPickerTransfers", isDirectory: true)

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: false) { received in
            try Self(copying: received.file)
        }
        FileRepresentation(importedContentType: .movie, shouldAttemptToOpenInPlace: false) { received in
            try Self(copying: received.file)
        }
    }

    /// `ReceivedTransferredFile.file` is only valid while the importing
    /// closure is running. Keep an app-owned copy before returning it.
    private init(copying source: URL) throws {
        let directory = Self.transferRoot
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: destination)
        self.fileURL = destination
    }
}

enum PhotoImportCapacityError: Error, Equatable, Sendable {
    case fileSizeUnavailable
    case capacityUnavailable
    case invalidFileSize
    case arithmeticOverflow
    case insufficientCapacity(requiredBytes: Int64, availableBytes: Int64)
}

/// Bounds each PhotosPicker transfer by bytes, not by an arbitrary item count.
/// Two copies are needed while a file moves from the provider to staging and
/// then to `Items/`; one fifth of the observed free capacity remains reserved.
enum PhotoImportCapacityPolicy {
    typealias ResourceReader = @Sendable (URL) throws -> (fileSize: Int64?, availableCapacity: Int64?)

    nonisolated static func validate(
        fileAt url: URL,
        alreadyReservedBytes: Int64 = 0,
        reader: ResourceReader? = nil
    ) throws -> Int64 {
        let values = try (reader ?? readResourceValues)(url)
        guard let fileSize = values.fileSize else { throw PhotoImportCapacityError.fileSizeUnavailable }
        guard let availableCapacity = values.availableCapacity, availableCapacity >= 0 else {
            throw PhotoImportCapacityError.capacityUnavailable
        }
        return try validate(
            fileSize: fileSize,
            availableCapacity: availableCapacity,
            alreadyReservedBytes: alreadyReservedBytes)
    }

    nonisolated static func validate(
        fileSize: Int64,
        availableCapacity: Int64,
        alreadyReservedBytes: Int64 = 0
    ) throws -> Int64 {
        guard fileSize >= 0 else { throw PhotoImportCapacityError.invalidFileSize }
        guard availableCapacity >= 0 else { throw PhotoImportCapacityError.capacityUnavailable }
        guard alreadyReservedBytes >= 0 else { throw PhotoImportCapacityError.invalidFileSize }
        let (requiredBytes, overflow) = fileSize.multipliedReportingOverflow(by: 2)
        guard !overflow else { throw PhotoImportCapacityError.arithmeticOverflow }
        let (cumulativeRequiredBytes, cumulativeOverflow) = alreadyReservedBytes.addingReportingOverflow(requiredBytes)
        guard !cumulativeOverflow else { throw PhotoImportCapacityError.arithmeticOverflow }
        let reservedBytes = availableCapacity / 5
        let usableCapacity = availableCapacity - reservedBytes
        guard cumulativeRequiredBytes <= usableCapacity else {
            throw PhotoImportCapacityError.insufficientCapacity(
                requiredBytes: cumulativeRequiredBytes,
                availableBytes: availableCapacity)
        }
        return fileSize
    }

    nonisolated static func message(for error: PhotoImportCapacityError) -> String {
        switch error {
        case .fileSizeUnavailable, .invalidFileSize:
            "Não foi possível medir um arquivo selecionado em Fotos."
        case .capacityUnavailable:
            "Não foi possível verificar o espaço livre para continuar a importação de Fotos."
        case .arithmeticOverflow, .insufficientCapacity:
            "Não há espaço livre suficiente para continuar a importação de Fotos."
        }
    }

    private nonisolated static func readResourceValues(for url: URL) throws -> (fileSize: Int64?, availableCapacity: Int64?) {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ])
        return (
            fileSize: values.fileSize.map(Int64.init),
            availableCapacity: values.volumeAvailableCapacityForImportantUsage
        )
    }
}

enum PhotoImportStaging {
    nonisolated static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Mural/PhotoImportStaging", isDirectory: true)

    static func directory(for operationID: UUID) throws -> URL {
        PhotoImportCleanup.sweep()
        guard let root else { throw CocoaError(.fileNoSuchFile) }
        let directory = root.appendingPathComponent(operationID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @concurrent
    nonisolated static func copy(
        _ source: URL,
        to directory: URL,
        index: Int,
        contentTypeIdentifier: String
    ) async throws -> URL {
        try Task.checkCancellation()
        guard let type = UTType(identifier: contentTypeIdentifier, allowUndeclared: false),
            let fileExtension = type.preferredFilenameExtension,
            !fileExtension.isEmpty
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destination = directory.appendingPathComponent("\(index)-\(UUID().uuidString).\(fileExtension)")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Removes only old, UUID-named artifacts owned by the two Photo import roots.
/// Active transfer URLs are registered while a session owns them, so a long
/// running operation is never swept merely because it crossed the age bound.
enum PhotoImportCleanup {
    private nonisolated static let registry = ActiveTransferRegistry()
    nonisolated static let maxAge: TimeInterval = 24 * 60 * 60

    nonisolated static func register(_ url: URL) {
        registry.insert(url.standardizedFileURL)
    }

    nonisolated static func unregister(_ urls: [URL]) {
        for url in urls { registry.remove(url.standardizedFileURL) }
    }

    @discardableResult
    nonisolated static func sweep(
        roots: [URL]? = nil,
        now: Date = .now,
        maxAge: TimeInterval = PhotoImportCleanup.maxAge
    ) -> [URL] {
        let roots = roots ?? [PhotoImportStaging.root, PhotoPickerFile.transferRoot].compactMap { $0 }
        var removed: [URL] = []
        for root in roots {
            guard
                let entries = try? FileManager.default.contentsOfDirectory(
                    at: root,
                    includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles])
            else { continue }
            for entry in entries {
                guard UUID(uuidString: entry.lastPathComponent) != nil,
                    !registry.contains(entry.standardizedFileURL),
                    let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey]),
                    let modified = values.contentModificationDate,
                    now.timeIntervalSince(modified) > maxAge,
                    (try? FileManager.default.removeItem(at: entry)) != nil
                else { continue }
                removed.append(entry)
            }
        }
        return removed
    }
}

private final class ActiveTransferRegistry: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var urls: Set<URL> = []

    nonisolated func insert(_ url: URL) {
        lock.lock()
        urls.insert(url)
        lock.unlock()
    }

    nonisolated func remove(_ url: URL) {
        lock.lock()
        urls.remove(url)
        lock.unlock()
    }

    nonisolated func contains(_ url: URL) -> Bool {
        lock.lock()
        let result = urls.contains(url)
        lock.unlock()
        return result
    }
}
