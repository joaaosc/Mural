import Foundation

/// Repositório isolado por mural. Todas as operações passam pelo mesmo actor e
/// nenhum caminho global ou "mural atual" participa da leitura ou gravação.
public actor BoardRepository {
    public let rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public func packageURL(for id: BoardID) -> URL {
        rootDirectory.appendingPathComponent("\(id.rawValue.uuidString).mural", isDirectory: true)
    }

    public func load(_ id: BoardID) throws -> BoardRepositoryLoadResult? {
        let package = packageURL(for: id)
        let boardURL = package.appendingPathComponent("board.json")
        guard FileManager.default.fileExists(atPath: boardURL.path) else { return nil }

        let manifest: BoardManifest
        let manifestURL = package.appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            do {
                manifest = try decode(BoardManifest.self, from: Data(contentsOf: manifestURL))
            } catch {
                throw BoardRepositoryError.corruptedManifest(String(describing: error))
            }
        } else {
            manifest = BoardManifest(id: id)
        }
        guard manifest.id == id else {
            throw BoardRepositoryError.identityMismatch(expected: id, actual: manifest.id)
        }

        let board: Board
        do {
            board = try decode(Board.self, from: Data(contentsOf: boardURL))
        } catch {
            throw BoardRepositoryError.corruptedBoard(String(describing: error))
        }

        let viewStateURL = package.appendingPathComponent("view-state.json")
        guard FileManager.default.fileExists(atPath: viewStateURL.path) else {
            let validation = BoardWorkspaceState(contentRevision: manifest.contentRevision)
                .canonicalized(for: board)
            return BoardRepositoryLoadResult(
                snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: validation.state),
                workspaceStatus: .missing,
                workspaceIssues: validation.issues
            )
        }

        do {
            let loaded = try decode(BoardWorkspaceState.self, from: Data(contentsOf: viewStateURL))
            var validation = loaded.canonicalized(for: board)
            if validation.state.contentRevision != manifest.contentRevision {
                var state = validation.state
                state.contentRevision = manifest.contentRevision
                validation = WorkspaceValidationResult(
                    state: state,
                    issues: validation.issues + [.contentRevisionAdjusted]
                )
            }
            return BoardRepositoryLoadResult(
                snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: validation.state),
                workspaceStatus: .loaded,
                workspaceIssues: validation.issues
            )
        } catch {
            let quarantineName = "view-state-corrupt-\(UUID().uuidString).json"
            let quarantineURL = package.appendingPathComponent(quarantineName)
            do {
                try FileManager.default.moveItem(at: viewStateURL, to: quarantineURL)
                let validation = BoardWorkspaceState(contentRevision: manifest.contentRevision)
                    .canonicalized(for: board)
                return BoardRepositoryLoadResult(
                    snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: validation.state),
                    workspaceStatus: .quarantined(filename: quarantineName),
                    workspaceIssues: validation.issues
                )
            } catch {
                let validation = BoardWorkspaceState(contentRevision: manifest.contentRevision)
                    .canonicalized(for: board)
                return BoardRepositoryLoadResult(
                    snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: validation.state),
                    workspaceStatus: .quarantineFailed(String(describing: error)),
                    workspaceIssues: validation.issues
                )
            }
        }
    }

    public func load(id: BoardID) throws -> BoardRepositoryLoadResult? {
        try load(id)
    }

    public func save(_ snapshot: BoardRepositorySnapshot) throws {
        let id = snapshot.manifest.id
        let package = packageURL(for: id)
        let existingManifest = try existingManifest(at: package)
        if let existingManifest,
            snapshot.manifest.contentRevision < existingManifest.contentRevision
                || snapshot.manifest.workspaceRevision < existingManifest.workspaceRevision
        {
            throw BoardRepositoryError.staleRevision(
                currentContent: existingManifest.contentRevision,
                incomingContent: snapshot.manifest.contentRevision,
                currentWorkspace: existingManifest.workspaceRevision,
                incomingWorkspace: snapshot.manifest.workspaceRevision
            )
        }

        var manifest = snapshot.manifest
        manifest.updatedAt = max(manifest.updatedAt, manifest.createdAt)
        var workspace = snapshot.workspace.validated(for: snapshot.board)
        // A workspace acompanha a revisão do conteúdo no mesmo commit lógico;
        // não é permitido carregar uma combinação de gerações diferentes.
        workspace.contentRevision = manifest.contentRevision
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let staging = rootDirectory.appendingPathComponent(
            ".\(id.rawValue.uuidString).mural-staging-\(UUID().uuidString)", isDirectory: true)
        let backup = rootDirectory.appendingPathComponent(".\(id.rawValue.uuidString).mural-backup-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let items = staging.appendingPathComponent("Items", isDirectory: true)
            try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
            let oldItems = package.appendingPathComponent("Items", isDirectory: true)
            if FileManager.default.fileExists(atPath: oldItems.path) {
                try FileManager.default.removeItem(at: items)
                try FileManager.default.copyItem(at: oldItems, to: items)
            }
            try encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try encode(snapshot.board).write(to: staging.appendingPathComponent("board.json"), options: .atomic)
            try encode(workspace).write(to: staging.appendingPathComponent("view-state.json"), options: .atomic)

            let hadExisting = FileManager.default.fileExists(atPath: package.path)
            if hadExisting { try FileManager.default.moveItem(at: package, to: backup) }
            do {
                try FileManager.default.moveItem(at: staging, to: package)
            } catch {
                if hadExisting { try? FileManager.default.moveItem(at: backup, to: package) }
                throw error
            }
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
        } catch let error as BoardRepositoryError {
            throw error
        } catch {
            throw BoardRepositoryError.io(String(describing: error))
        }
        if FileManager.default.fileExists(atPath: staging.path) { try? FileManager.default.removeItem(at: staging) }
        if FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.removeItem(at: backup) }
    }

    public func save(id: BoardID, board: Board, workspace: BoardWorkspaceState, manifest: BoardManifest? = nil) throws {
        var resolved = manifest ?? BoardManifest(id: id)
        guard resolved.id == id else {
            throw BoardRepositoryError.identityMismatch(expected: id, actual: resolved.id)
        }
        resolved.id = id
        try save(BoardRepositorySnapshot(manifest: resolved, board: board, workspace: workspace))
    }

    private func existingManifest(at package: URL) throws -> BoardManifest? {
        let url = package.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do { return try decode(BoardManifest.self, from: Data(contentsOf: url)) } catch {
            throw BoardRepositoryError.corruptedManifest(String(describing: error))
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        // ISO-8601 sem frações perde os nanossegundos de Date e quebra o
        // round-trip exato exigido pelo domínio. O número JSON mantém o valor
        // binário de segundos sem depender de locale.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.timeIntervalSinceReferenceDate)
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
        }
        return try decoder.decode(type, from: data)
    }
}
