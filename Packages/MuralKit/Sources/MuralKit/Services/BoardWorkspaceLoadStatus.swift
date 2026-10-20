import Foundation

public enum BoardWorkspaceLoadStatus: Equatable, Sendable {
    case loaded
    case missing
    case quarantined(filename: String)
    case quarantineFailed(String)
}
