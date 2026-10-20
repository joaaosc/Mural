import Foundation

/// Filtro que pode sobreviver à troca de processo e de mural.
public enum WorkspaceFilter: String, Codable, CaseIterable, Equatable, Sendable {
    case notes
    case folders
    case tasks

    public func matches(_ kind: ItemKind) -> Bool {
        switch self {
        case .notes: kind == .text || kind == .sticky
        case .folders: kind == .folder
        case .tasks: kind == .checklist
        }
    }
}

/// Nome mais explícito para integrações que não usam a palavra Workspace.
public typealias PersistedBoardFilter = WorkspaceFilter
public typealias BoardFilter = WorkspaceFilter
