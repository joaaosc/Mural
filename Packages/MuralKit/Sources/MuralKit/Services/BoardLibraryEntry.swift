import Foundation

public struct BoardLibraryEntry: Codable, Equatable, Sendable {
    public let manifest: BoardManifest
    public let route: BoardRoute

    public init(manifest: BoardManifest, route: BoardRoute) {
        self.manifest = manifest
        self.route = route
    }
}

/// Package da biblioteca que não pôde ser lido e por quê (para mostrar ao usuário).
public struct BoardLibraryIssue: Equatable, Sendable {
    public let packageName: String
    public let reason: String

    public init(packageName: String, reason: String) {
        self.packageName = packageName
        self.reason = reason
    }
}

public struct BoardLibraryListing: Equatable, Sendable {
    public let entries: [BoardLibraryEntry]
    public let unreadable: [BoardLibraryIssue]

    public init(entries: [BoardLibraryEntry], unreadable: [BoardLibraryIssue] = []) {
        self.entries = entries
        self.unreadable = unreadable
    }
}
