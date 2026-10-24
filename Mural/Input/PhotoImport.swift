import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// File-backed representation used by PhotosPicker. The picker supplies a
/// temporary URL; the session copies it into its own staging directory before
/// handing it to the domain importer.
struct PhotoPickerFile: Transferable, Sendable {
    let fileURL: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: false) { received in
            Self(fileURL: received.file)
        }
        FileRepresentation(importedContentType: .movie, shouldAttemptToOpenInPlace: false) { received in
            Self(fileURL: received.file)
        }
    }
}

enum PhotoImportStaging {
    static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Mural/PhotoImportStaging", isDirectory: true)

    static func directory(for operationID: UUID) throws -> URL {
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
        let type = UTType(identifier: contentTypeIdentifier, allowUndeclared: false)
        let fileExtension = type?.preferredFilenameExtension ?? source.pathExtension
        guard !fileExtension.isEmpty else {
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
