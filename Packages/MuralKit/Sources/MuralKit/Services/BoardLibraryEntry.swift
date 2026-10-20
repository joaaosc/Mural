import Foundation

public struct BoardLibraryEntry: Codable, Equatable, Sendable {
    public let manifest: BoardManifest
    public let route: BoardRoute

    public init(manifest: BoardManifest, route: BoardRoute) {
        self.manifest = manifest
        self.route = route
    }
}
