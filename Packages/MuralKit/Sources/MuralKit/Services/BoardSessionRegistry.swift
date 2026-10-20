import Foundation

public actor BoardSessionRegistry {
    public let library: BoardLibrary
    private var sessions: [BoardID: BoardSession] = [:]

    public init(library: BoardLibrary) {
        self.library = library
    }

    public func open(_ route: BoardRoute) async throws -> BoardSession {
        let id: BoardID
        switch route {
        case .library:
            throw BoardLibraryError.unavailableRoute(route)
        case .welcomeDraft(let draftID), .saved(let draftID):
            id = draftID
        }
        if let existing = sessions[id] { return existing }
        guard let snapshot = try await library.open(route) else {
            throw BoardLibraryError.unavailableRoute(route)
        }
        let session = BoardSession(snapshot: snapshot, repository: try await library.repository(for: route))
        sessions[id] = session
        return session
    }

    public func close(_ id: BoardID) {
        sessions.removeValue(forKey: id)
    }

    public func session(for id: BoardID) -> BoardSession? {
        sessions[id]
    }

    @discardableResult
    public func promoteWelcomeDraft(name: String) async throws -> BoardRoute {
        let state = try await library.lifecycleState()
        let draftID = state?.stableWelcomeID
        let route = try await library.promoteWelcomeDraft(name: name)
        if let draftID { sessions.removeValue(forKey: draftID) }
        return route
    }
}
