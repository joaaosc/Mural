import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The portable Mural package. A package is a directory whose four root
    /// entries are `manifest.json`, `board.json`, `view-state.json`, and `Items`.
    nonisolated static let muralPackage = UTType(
        exportedAs: "com.joaocosta.mural",
        conformingTo: .package)
}

/// A lightweight adapter around a package that has already been materialized
/// by `BoardLibrary`. SwiftUI asks for the snapshot on the main actor, but the
/// writer reads and copies the package on its background writer task.
final class MuralPackageDocument: WritableDocument {
    struct Snapshot: Sendable {
        let stagingURL: URL
    }

    static let writableContentTypes: [UTType] = [.muralPackage]

    private let stagingURL: URL

    init(stagingURL: URL) {
        self.stagingURL = stagingURL.standardizedFileURL
    }

    @MainActor
    func snapshot(contentType: UTType) async throws -> sending Snapshot {
        guard contentType == .muralPackage else {
            throw MuralPackageDocumentError.unsupportedContentType(contentType.identifier)
        }
        return Snapshot(stagingURL: stagingURL)
    }

    nonisolated func writer(
        configuration: sending WriteConfiguration
    ) -> sending FileWrapperDocumentWriter<Snapshot> {
        FileWrapperDocumentWriter(configuration) { snapshot, _ in
            // `FileWrapperDocumentWriter` invokes this closure on its writer
            // task. Keeping it synchronous avoids moving a non-Sendable
            // FileWrapper through another task boundary.
            try FileWrapper(url: snapshot.stagingURL, options: [])
        }
    }
}

enum MuralPackageDocumentError: Error, Equatable, Sendable {
    case unsupportedContentType(String)
}
