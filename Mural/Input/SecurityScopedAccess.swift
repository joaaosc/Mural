import Foundation
import MuralKit

/// Abre o acesso de sandbox de URLs vindas do seletor de arquivos durante a importação.
enum SecurityScopedAccess {
    typealias Start = (URL) -> Bool
    typealias Stop = (URL) -> Void

    static func withAccess<T>(to urls: [URL], _ body: () -> T) -> T {
        withAccess(
            to: urls,
            start: { $0.startAccessingSecurityScopedResource() },
            stop: { $0.stopAccessingSecurityScopedResource() },
            body)
    }

    static func withAccess<T>(
        to urls: [URL],
        start: @escaping Start,
        stop: @escaping Stop,
        _ body: () -> T
    ) -> T {
        let opened = urls.filter(start)
        defer {
            for url in opened { stop(url) }
        }
        return body()
    }

    /// Keeps the security scope alive for the complete asynchronous copy. The
    /// file importer owns the initial scope; calling start here is harmless and
    /// makes the lifetime explicit for injected panels and tests.
    static func withAccess<T>(
        to urls: [URL],
        start: @escaping Start,
        stop: @escaping Stop,
        operation: () async throws -> T
    ) async rethrows -> T {
        let opened = urls.filter(start)
        defer {
            for url in opened { stop(url) }
        }
        return try await operation()
    }

    static func withAccess<T>(
        to urls: [URL],
        operation: () async throws -> T
    ) async rethrows -> T {
        try await withAccess(
            to: urls,
            start: { $0.startAccessingSecurityScopedResource() },
            stop: { $0.stopAccessingSecurityScopedResource() },
            operation: operation)
    }
}

/// Shared boundary for packages arriving from a file panel or Finder.  The
/// library always imports into its own repository, so the external package is
/// never adopted as an active board source.
enum MuralPackageImport {
    static func importAsCopy(
        from source: URL,
        using library: BoardLibrary
    ) async throws -> BoardImportResult {
        try await SecurityScopedAccess.withAccess(to: [source]) {
            try await library.importPackageWithReport(from: source)
        }
    }
}
