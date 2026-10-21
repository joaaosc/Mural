import Foundation

/// Repositório isolado por mural. Todas as operações passam pelo mesmo actor e
/// nenhum caminho global ou "mural atual" participa da leitura ou gravação.
public actor BoardRepository {
    public let rootDirectory: URL
    public let packageName: String?
    private var faultInjection: BoardRepositoryFaultInjection

    public init(
        rootDirectory: URL,
        packageName: String? = nil,
        faultInjection: BoardRepositoryFaultInjection = .none
    ) {
        self.rootDirectory = rootDirectory
        self.packageName = packageName
        self.faultInjection = faultInjection
    }

    public func packageURL(for id: BoardID) -> URL {
        rootDirectory.appendingPathComponent(
            packageName ?? "\(id.rawValue.uuidString).mural", isDirectory: true)
    }

    /// Materializes one coherent repository version without an actor suspension
    /// between reading JSON and copying its assets.
    func materializePackage(for id: BoardID, to destination: URL) throws {
        guard let loaded = try load(id) else { throw BoardRepositoryError.boardNotFound(id) }
        let package = destination.standardizedFileURL
        guard !FileManager.default.fileExists(atPath: package.path) else {
            throw BoardRepositoryError.io("materialization destination exists")
        }
        var completed = false
        defer {
            if !completed, FileManager.default.fileExists(atPath: package.path) {
                try? FileManager.default.removeItem(at: package)
            }
        }
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let items = package.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        let sourceItems = packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        if FileManager.default.fileExists(atPath: sourceItems.path) {
            try FileManager.default.removeItem(at: items)
            try FileManager.default.copyItem(at: sourceItems, to: items)
        }
        do {
            try encode(loaded.snapshot.manifest).write(to: package.appendingPathComponent("manifest.json"), options: .atomic)
            try encode(loaded.snapshot.board).write(to: package.appendingPathComponent("board.json"), options: .atomic)
            try encode(loaded.snapshot.workspace).write(to: package.appendingPathComponent("view-state.json"), options: .atomic)
        } catch {
            throw BoardRepositoryError.io(String(describing: error))
        }
        completed = true
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
            guard manifest.schemaVersion <= BoardManifest.currentSchemaVersion else {
                throw BoardRepositoryError.futureManifestSchema(manifest.schemaVersion)
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
            guard loaded.schemaVersion <= BoardWorkspaceState.currentSchemaVersion else {
                return BoardRepositoryLoadResult(
                    snapshot: BoardRepositorySnapshot(
                        manifest: manifest,
                        board: board,
                        workspace: BoardWorkspaceState(contentRevision: manifest.contentRevision)
                    ),
                    workspaceStatus: .futureSchema(version: loaded.schemaVersion)
                )
            }
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

    public func save(_ snapshot: BoardRepositorySnapshot) async throws {
        try await save(snapshot, copyingItemsFrom: nil)
    }

    public func save(_ snapshot: BoardRepositorySnapshot, copyingItemsFrom sourceItems: URL?) async throws {
        try await save(snapshot, copyingItemsFrom: sourceItems, preservingWorkspaceDiagnostic: nil)
    }

    func save(
        _ snapshot: BoardRepositorySnapshot,
        copyingItemsFrom sourceItems: URL?,
        preservingWorkspaceDiagnostic diagnostic: Data?
    ) async throws {
        let id = snapshot.manifest.id
        let package = packageURL(for: id)
        let existingManifest = try existingManifest(at: package)

        var manifest = snapshot.manifest
        guard manifest.schemaVersion <= BoardManifest.currentSchemaVersion else {
            throw BoardRepositoryError.futureManifestSchema(manifest.schemaVersion)
        }
        guard snapshot.workspace.schemaVersion <= BoardWorkspaceState.currentSchemaVersion else {
            throw BoardRepositoryError.futureWorkspaceSchema(snapshot.workspace.schemaVersion)
        }
        manifest.updatedAt = max(manifest.updatedAt, manifest.createdAt)
        var workspace = snapshot.workspace.validated(for: snapshot.board)
        // A workspace acompanha a revisão do conteúdo no mesmo commit lógico;
        // não é permitido carregar uma combinação de gerações diferentes.
        workspace.contentRevision = manifest.contentRevision

        if let existingManifest {
            if manifest.contentRevision < existingManifest.contentRevision
                || manifest.workspaceRevision < existingManifest.workspaceRevision
            {
                throw BoardRepositoryError.staleRevision(
                    currentContent: existingManifest.contentRevision,
                    incomingContent: manifest.contentRevision,
                    currentWorkspace: existingManifest.workspaceRevision,
                    incomingWorkspace: manifest.workspaceRevision
                )
            }
            if manifest.contentRevision == existingManifest.contentRevision,
                manifest.workspaceRevision == existingManifest.workspaceRevision
            {
                let currentBoard = try decode(Board.self, from: Data(contentsOf: package.appendingPathComponent("board.json")))
                let currentWorkspace = try loadWorkspaceForComparison(at: package, board: currentBoard)
                guard currentBoard == snapshot.board, currentWorkspace == workspace else {
                    throw BoardRepositoryError.conflictingRevision(
                        content: manifest.contentRevision,
                        workspace: manifest.workspaceRevision
                    )
                }
                if manifest.name == existingManifest.name { return }
            }
        }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)

        let staging = rootDirectory.appendingPathComponent(
            ".\(id.rawValue.uuidString).mural-staging-\(UUID().uuidString)", isDirectory: true)
        let backup = rootDirectory.appendingPathComponent(".\(id.rawValue.uuidString).mural-backup-\(UUID().uuidString)", isDirectory: true)
        var hadExisting = false
        var didSwap = false
        defer {
            if FileManager.default.fileExists(atPath: staging.path) { try? FileManager.default.removeItem(at: staging) }
            if FileManager.default.fileExists(atPath: backup.path) {
                if !FileManager.default.fileExists(atPath: package.path) {
                    try? FileManager.default.moveItem(at: backup, to: package)
                } else {
                    try? FileManager.default.removeItem(at: backup)
                }
            }
        }
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let items = staging.appendingPathComponent("Items", isDirectory: true)
            try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
            let oldItems = package.appendingPathComponent("Items", isDirectory: true)
            let itemsSource = sourceItems ?? oldItems
            if FileManager.default.fileExists(atPath: itemsSource.path) {
                try FileManager.default.removeItem(at: items)
                try FileManager.default.copyItem(at: itemsSource, to: items)
            }
            try copyKnownDiagnostics(from: package, to: staging)
            if let diagnostic {
                let diagnosticURL = staging.appendingPathComponent(".view-state-corrupt-\(UUID().uuidString).json")
                try diagnostic.write(to: diagnosticURL, options: .atomic)
            }
            try encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try encode(snapshot.board).write(to: staging.appendingPathComponent("board.json"), options: .atomic)
            try encode(workspace).write(to: staging.appendingPathComponent("view-state.json"), options: .atomic)

            hadExisting = FileManager.default.fileExists(atPath: package.path)
            try await inject(.beforeSwap)
            if hadExisting { try FileManager.default.moveItem(at: package, to: backup) }
            try FileManager.default.moveItem(at: staging, to: package)
            didSwap = true
            try await inject(.afterSwap)
        } catch let error as BoardRepositoryError {
            if didSwap { try? FileManager.default.removeItem(at: package) }
            if hadExisting, FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(at: backup, to: package)
            }
            throw error
        } catch {
            if didSwap { try? FileManager.default.removeItem(at: package) }
            if hadExisting, FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(at: backup, to: package)
            }
            throw BoardRepositoryError.io(String(describing: error))
        }
    }

    public func save(id: BoardID, board: Board, workspace: BoardWorkspaceState, manifest: BoardManifest? = nil) async throws {
        var resolved = manifest ?? BoardManifest(id: id)
        guard resolved.id == id else {
            throw BoardRepositoryError.identityMismatch(expected: id, actual: resolved.id)
        }
        resolved.id = id
        try await save(BoardRepositorySnapshot(manifest: resolved, board: board, workspace: workspace))
    }

    private func existingManifest(at package: URL) throws -> BoardManifest? {
        let url = package.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let manifest = try decode(BoardManifest.self, from: Data(contentsOf: url))
            guard manifest.schemaVersion <= BoardManifest.currentSchemaVersion else {
                throw BoardRepositoryError.futureManifestSchema(manifest.schemaVersion)
            }
            return manifest
        } catch let error as BoardRepositoryError {
            throw error
        } catch {
            throw BoardRepositoryError.corruptedManifest(String(describing: error))
        }
    }

    private func copyKnownDiagnostics(from package: URL, to staging: URL) throws {
        guard FileManager.default.fileExists(atPath: package.path) else { return }
        let entries = try FileManager.default.contentsOfDirectory(at: package, includingPropertiesForKeys: nil, options: [])
        for entry in entries
        where entry.lastPathComponent.hasPrefix(".view-state-corrupt-")
            || entry.lastPathComponent.hasPrefix("view-state-corrupt-")
        {
            let attributes = try FileManager.default.attributesOfItem(atPath: entry.path)
            guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
                throw BoardRepositoryError.io("invalid workspace diagnostic")
            }
            try FileManager.default.copyItem(at: entry, to: staging.appendingPathComponent(entry.lastPathComponent))
        }
    }

    private func loadWorkspaceForComparison(at package: URL, board: Board) throws -> BoardWorkspaceState {
        let url = package.appendingPathComponent("view-state.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return BoardWorkspaceState(contentRevision: 0).validated(for: board)
        }
        let workspace = try decode(BoardWorkspaceState.self, from: Data(contentsOf: url))
        guard workspace.schemaVersion <= BoardWorkspaceState.currentSchemaVersion else {
            throw BoardRepositoryError.io("workspace schema futuro")
        }
        return workspace.validated(for: board)
    }

    private func inject(_ point: BoardRepositoryFaultPoint) async throws {
        if faultInjection.consume(point) {
            await faultInjection.gate?.waitForRelease()
            throw BoardRepositoryError.injectedFailure(point)
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
