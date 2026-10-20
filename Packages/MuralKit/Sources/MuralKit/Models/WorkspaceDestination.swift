import Foundation

/// Um nível navegável do mural. A sequência válida é validada contra `Board`.
public enum WorkspaceDestination: Codable, Equatable, Hashable, Sendable {
    case collection(UUID)
    case item(UUID)
}
