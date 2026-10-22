import Foundation

/// Garante uma única `BoardSession` viva por `BoardID`.
///
/// Abrir é single-flight: duas cenas que pedem o mesmo mural ao mesmo tempo recebem a
/// mesma instância, nunca dois escritores do mesmo package. Janelas usam `acquire` e
/// `release`; a sessão só é aposentada quando o último dono a solta e ela está limpa.
/// Uma sessão suja sem donos fica registrada para que a próxima janela a recupere.
public actor BoardSessionRegistry {
    public nonisolated let library: BoardLibrary
    private var sessions: [BoardID: BoardSession] = [:]
    private var opening: [BoardID: Task<BoardSession, Error>] = [:]
    private var owners: [BoardID: Int] = [:]

    public init(library: BoardLibrary) {
        self.library = library
    }

    public func open(_ route: BoardRoute) async throws -> BoardSession {
        let id = try Self.boardID(of: route)
        if let existing = sessions[id] { return existing }
        if let pending = opening[id] { return try await pending.value }

        let library = self.library
        let task = Task<BoardSession, Error> {
            guard let snapshot = try await library.open(route) else {
                throw BoardLibraryError.unavailableRoute(route)
            }
            return BoardSession(snapshot: snapshot, repository: try await library.repository(for: route))
        }
        opening[id] = task
        do {
            let session = try await task.value
            opening[id] = nil
            if let existing = sessions[id] { return existing }
            sessions[id] = session
            return session
        } catch {
            opening[id] = nil
            throw error
        }
    }

    /// Abre (ou reutiliza) a sessão e registra mais um dono.
    public func acquire(_ route: BoardRoute) async throws -> BoardSession {
        let id = try Self.boardID(of: route)
        owners[id, default: 0] += 1
        do {
            return try await open(route)
        } catch {
            dropOwner(of: id)
            throw error
        }
    }

    /// Solta um dono. Devolve `true` quando a sessão foi aposentada e removida; uma
    /// sessão suja continua registrada (e viva) para não perder alterações.
    @discardableResult
    public func release(_ id: BoardID) async -> Bool {
        dropOwner(of: id)
        guard owners[id] == nil else { return false }
        guard let session = sessions[id] else { return true }
        guard await !session.isDirty else { return false }
        // Outra janela pode ter adquirido a sessão durante a suspensão acima.
        guard owners[id] == nil, sessions[id] === session else { return false }
        sessions[id] = nil
        await session.retire()
        return true
    }

    /// Remoção forçada (renomeação antiga, testes). A sessão removida é aposentada.
    public func close(_ id: BoardID) async {
        owners[id] = nil
        guard let session = sessions.removeValue(forKey: id) else { return }
        await session.retire()
    }

    public func session(for id: BoardID) -> BoardSession? {
        sessions[id]
    }

    public func ownerCount(for id: BoardID) -> Int {
        owners[id] ?? 0
    }

    @discardableResult
    public func promoteWelcomeDraft(name: String) async throws -> BoardRoute {
        let state = try await library.lifecycleState()
        let draftID = state?.stableWelcomeID
        let route = try await library.promoteWelcomeDraft(name: name)
        if let draftID {
            owners[draftID] = nil
            if let draft = sessions.removeValue(forKey: draftID) {
                // Um autosave atrasado da janela do rascunho não pode recriar o package.
                await draft.retire()
            }
        }
        return route
    }

    private func dropOwner(of id: BoardID) {
        let remaining = (owners[id] ?? 0) - 1
        owners[id] = remaining > 0 ? remaining : nil
    }

    private static func boardID(of route: BoardRoute) throws -> BoardID {
        switch route {
        case .library:
            throw BoardLibraryError.unavailableRoute(route)
        case .welcomeDraft(let id), .saved(let id):
            return id
        }
    }
}
