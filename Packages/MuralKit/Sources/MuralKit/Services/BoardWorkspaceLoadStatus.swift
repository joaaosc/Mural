import Foundation

public enum BoardWorkspaceLoadStatus: Equatable, Sendable {
    case loaded
    case missing
    case futureSchema(version: Int)
    case quarantined(filename: String)
    case quarantineFailed(String)
}
