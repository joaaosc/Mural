import Foundation

public enum LibraryLifecycle: String, Codable, Equatable, Sendable {
    case intact
    case draft
    case promoted
    case discarded
}
