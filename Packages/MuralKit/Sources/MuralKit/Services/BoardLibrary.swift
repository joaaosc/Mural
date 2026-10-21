import Foundation

/// Biblioteca de murais e ciclo de vida do rascunho inicial.
public actor BoardLibrary {
    public let rootDirectory: URL
    public let boardsDirectory: URL
    public let draftsDirectory: URL
    public let transfersDirectory: URL
    public let importStagingDirectory: URL
    public let libraryStateURL: URL

    private let savedRepository: BoardRepository
    private let draftRepository: BoardRepository
    private var faultInjection: BoardLibraryFaultInjection
    private var bootstrapTask: Task<LibraryState, Error>?

    public init(
        rootDirectory: URL = BoardStore.defaultDirectory(),
        faultInjection: BoardLibraryFaultInjection = .none,
        repositoryFaultInjection: BoardRepositoryFaultInjection = .none
    ) {
        self.rootDirectory = rootDirectory
        self.boardsDirectory = rootDirectory.appendingPathComponent("Boards", isDirectory: true)
        self.draftsDirectory = rootDirectory.appendingPathComponent("Drafts", isDirectory: true)
        self.transfersDirectory = rootDirectory.appendingPathComponent("Transfers", isDirectory: true)
        self.importStagingDirectory = rootDirectory.appendingPathComponent("ImportStaging", isDirectory: true)
        self.libraryStateURL = rootDirectory.appendingPathComponent("LibraryState.json")
        self.savedRepository = BoardRepository(
            rootDirectory: rootDirectory.appendingPathComponent("Boards", isDirectory: true),
            faultInjection: repositoryFaultInjection)
        self.draftRepository = BoardRepository(
            rootDirectory: rootDirectory.appendingPathComponent("Drafts", isDirectory: true),
            packageName: "Welcome.mural",
            faultInjection: repositoryFaultInjection)
        self.faultInjection = faultInjection
        self.bootstrapTask = nil
    }

    public static func defaultRootDirectory() -> URL {
        BoardStore.defaultDirectory()
    }

    public func bootstrap() async throws -> LibraryState {
        if let bootstrapTask {
            return try await bootstrapTask.value
        }

        let bootstrapTask = Task { [self] in
            defer { self.bootstrapTask = nil }
            return try await performBootstrap()
        }
        self.bootstrapTask = bootstrapTask
        return try await bootstrapTask.value
    }

    private func performBootstrap() async throws -> LibraryState {
        try makeDirectories()
        var state = try loadState() ?? LibraryState()
        guard state.schemaVersion <= LibraryState.currentSchemaVersion else {
            throw BoardLibraryError.futureSchema(state.schemaVersion)
        }
        if !FileManager.default.fileExists(atPath: libraryStateURL.path) {
            try saveState(state)
        }

        switch state.lifecycle {
        case .intact:
            let existingDraftURL = await draftRepository.packageURL(for: state.stableWelcomeID)
            if FileManager.default.fileExists(atPath: existingDraftURL.path) {
                try validateCompletePackage(existingDraftURL)
            }
            if let existingDraft = try await draftRepository.load(state.stableWelcomeID) {
                // Recupera publicação completa que sobreviveu a uma queda antes
                // do marcador de lifecycle.
                _ = existingDraft
                state.lifecycle = .draft
                try saveState(state)
                return state
            }
            let board: Board
            let legacyItems = rootDirectory.appendingPathComponent("Items", isDirectory: true)
            do {
                board = try BoardStore(directory: rootDirectory).load() ?? SampleBoard.make()
            } catch {
                throw BoardLibraryError.io("legado ilegível: \(error)")
            }
            let manifest = BoardManifest(id: state.stableWelcomeID, name: "Rascunho de exemplo")
            let snapshot = BoardRepositorySnapshot(
                manifest: manifest,
                board: board,
                workspace: .default
            )
            try await inject(.beforeDraftPublish)
            if FileManager.default.fileExists(atPath: legacyItems.path) {
                try await draftRepository.save(snapshot, copyingItemsFrom: legacyItems)
            } else {
                try await draftRepository.save(snapshot)
            }
            try await inject(.afterDraftPublish)
            state.lifecycle = .draft
            try saveState(state)
        case .draft:
            let draftURL = await draftRepository.packageURL(for: state.stableWelcomeID)
            if FileManager.default.fileExists(atPath: draftURL.path) {
                try validateCompletePackage(draftURL)
                guard try await draftRepository.load(state.stableWelcomeID) != nil else {
                    throw BoardLibraryError.unavailableRoute(.welcomeDraft(state.stableWelcomeID))
                }
            } else if let promotedID = state.promotedBoardID,
                try await savedRepository.load(promotedID) != nil
            {
                try validateCompletePackage(await savedRepository.packageURL(for: promotedID))
                state.lifecycle = .promoted
                try saveState(state)
            } else {
                throw BoardLibraryError.unavailableRoute(.welcomeDraft(state.stableWelcomeID))
            }
        case .promoted:
            if let promotedID = state.promotedBoardID {
                try validateCompletePackage(await savedRepository.packageURL(for: promotedID))
            }
            guard let promotedID = state.promotedBoardID,
                try await savedRepository.load(promotedID) != nil
            else {
                throw BoardLibraryError.unavailableRoute(.saved(state.promotedBoardID ?? state.stableWelcomeID))
            }
        case .discarded:
            break
        }
        return state
    }

    public func migrateLegacyIfNeeded() async throws -> LibraryState {
        try await bootstrap()
    }

    public func lifecycleState() throws -> LibraryState? {
        try loadState()
    }

    public func listSaved() async throws -> [BoardLibraryEntry] {
        try makeDirectories()
        let entries = try FileManager.default.contentsOfDirectory(
            at: boardsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var result: [BoardLibraryEntry] = []
        for package in entries where package.pathExtension == "mural" {
            let manifestURL = package.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            let manifest = try decodeManifest(from: manifestURL)
            let expectedName = "\(manifest.id.rawValue.uuidString).mural"
            guard package.deletingLastPathComponent().standardizedFileURL == boardsDirectory.standardizedFileURL,
                package.lastPathComponent == expectedName
            else {
                throw BoardLibraryError.invalidPackage(package)
            }
            try validateCompletePackage(package)
            result.append(BoardLibraryEntry(manifest: manifest, route: .saved(manifest.id)))
        }
        return result.sorted {
            let nameOrder = $0.manifest.name.compare($1.manifest.name)
            return nameOrder == .orderedSame
                ? $0.manifest.id.rawValue.uuidString < $1.manifest.id.rawValue.uuidString
                : nameOrder == .orderedAscending
        }
    }

    public func list() async throws -> [BoardLibraryEntry] {
        let saved = try await listSaved()
        let state = try await bootstrap()
        guard state.lifecycle == .draft else { return saved }
        guard let result = try await draftRepository.load(state.stableWelcomeID) else {
            throw BoardLibraryError.unavailableRoute(.welcomeDraft(state.stableWelcomeID))
        }
        return saved + [BoardLibraryEntry(manifest: result.snapshot.manifest, route: .welcomeDraft(state.stableWelcomeID))]
    }

    public func createNamedBoard(_ name: String) async throws -> BoardRoute {
        _ = try await bootstrap()
        let id = BoardID()
        let snapshot = BoardRepositorySnapshot(
            manifest: BoardManifest(id: id, name: name),
            board: Board(),
            workspace: .default
        )
        try await savedRepository.save(snapshot)
        return .saved(id)
    }

    public func open(_ route: BoardRoute) async throws -> BoardRepositorySnapshot? {
        switch route {
        case .library:
            return nil
        case .welcomeDraft(let id):
            guard let state = try loadState(), state.lifecycle == .draft, state.stableWelcomeID == id else {
                throw BoardLibraryError.unavailableRoute(route)
            }
            try validateCompletePackage(await draftRepository.packageURL(for: id))
            guard let snapshot = try await draftRepository.load(id)?.snapshot,
                snapshot.manifest.id == id
            else { throw BoardLibraryError.unavailableRoute(route) }
            return snapshot
        case .saved(let id):
            try validateCompletePackage(await savedRepository.packageURL(for: id))
            guard let snapshot = try await savedRepository.load(id)?.snapshot,
                snapshot.manifest.id == id
            else { throw BoardLibraryError.unavailableRoute(route) }
            return snapshot
        }
    }

    public func rename(_ route: BoardRoute, to name: String) async throws -> BoardRoute {
        guard let snapshot = try await open(route) else { throw BoardLibraryError.unavailableRoute(route) }
        var manifest = snapshot.manifest
        manifest.name = name
        let renamed = BoardRepositorySnapshot(manifest: manifest, board: snapshot.board, workspace: snapshot.workspace)
        switch route {
        case .library:
            throw BoardLibraryError.unavailableRoute(route)
        case .welcomeDraft:
            try await draftRepository.save(renamed)
            return route
        case .saved:
            try await savedRepository.save(renamed)
            return route
        }
    }

    public func promoteWelcomeDraft(name: String) async throws -> BoardRoute {
        var state = try await bootstrap()
        guard state.lifecycle == .draft,
            let draft = try await draftRepository.load(state.stableWelcomeID)?.snapshot
        else { throw BoardLibraryError.unavailableRoute(.welcomeDraft(state.stableWelcomeID)) }

        let promotedID = state.promotedBoardID ?? BoardID()
        state.promotedBoardID = promotedID
        try saveState(state)
        let promotedRoute = BoardRoute.saved(promotedID)
        if try await savedRepository.load(promotedID) == nil {
            var manifest = draft.manifest
            manifest.id = promotedID
            manifest.name = name
            let snapshot = BoardRepositorySnapshot(manifest: manifest, board: draft.board, workspace: draft.workspace)
            try await inject(.beforePromotionPublish)
            try await savedRepository.save(
                snapshot,
                copyingItemsFrom: (await draftRepository.packageURL(for: state.stableWelcomeID)).appendingPathComponent(
                    "Items", isDirectory: true)
            )
            try await inject(.afterPromotionPublish)
        }
        state.lifecycle = .promoted
        try saveState(state)
        let draftPackage = await draftRepository.packageURL(for: state.stableWelcomeID)
        do {
            try FileManager.default.removeItem(at: draftPackage)
        } catch {
            if FileManager.default.fileExists(atPath: draftPackage.path) {
                throw BoardLibraryError.io(String(describing: error))
            }
        }
        return promotedRoute
    }

    public func discardWelcomeDraft() async throws {
        var state = try await bootstrap()
        guard state.lifecycle == .draft else { return }
        state.lifecycle = .discarded
        try saveState(state)
        try await inject(.beforeDiscardCleanup)
        do {
            try FileManager.default.removeItem(at: await draftRepository.packageURL(for: state.stableWelcomeID))
        } catch {
            if FileManager.default.fileExists(atPath: await draftRepository.packageURL(for: state.stableWelcomeID).path) {
                throw BoardLibraryError.io(String(describing: error))
            }
        }
    }

    public func stateURL() -> URL { libraryStateURL }

    public func repository(for route: BoardRoute) throws -> BoardRepository {
        switch route {
        case .library:
            throw BoardLibraryError.unavailableRoute(route)
        case .welcomeDraft:
            return draftRepository
        case .saved:
            return savedRepository
        }
    }

    private func makeDirectories() throws {
        do {
            for directory in [rootDirectory, boardsDirectory, draftsDirectory, transfersDirectory, importStagingDirectory] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
        } catch { throw BoardLibraryError.io(String(describing: error)) }
    }

    private func loadState() throws -> LibraryState? {
        guard FileManager.default.fileExists(atPath: libraryStateURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(LibraryState.self, from: Data(contentsOf: libraryStateURL))
        } catch { throw BoardLibraryError.corruptedLibraryState(String(describing: error)) }
    }

    private func saveState(_ state: LibraryState) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let temporary = libraryStateURL.appendingPathExtension("tmp-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: temporary) }
            try encoder.encode(state).write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: libraryStateURL.path) {
                _ = try FileManager.default.replaceItemAt(libraryStateURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: libraryStateURL)
            }
        } catch { throw BoardLibraryError.io(String(describing: error)) }
    }

    private func decodeManifest(from url: URL) throws -> BoardManifest {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                return Date(timeIntervalSinceReferenceDate: try container.decode(Double.self))
            }
            let manifest = try decoder.decode(BoardManifest.self, from: Data(contentsOf: url))
            guard manifest.schemaVersion <= BoardManifest.currentSchemaVersion else {
                throw BoardLibraryError.futureSchema(manifest.schemaVersion)
            }
            return manifest
        } catch let error as BoardLibraryError { throw error } catch {
            throw BoardLibraryError.invalidPackage(url.deletingLastPathComponent())
        }
    }

    private func validateCompletePackage(_ package: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: package.path, isDirectory: &isDirectory), isDirectory.boolValue,
            FileManager.default.fileExists(atPath: package.appendingPathComponent("manifest.json").path),
            FileManager.default.fileExists(atPath: package.appendingPathComponent("board.json").path),
            FileManager.default.fileExists(atPath: package.appendingPathComponent("view-state.json").path),
            FileManager.default.fileExists(atPath: package.appendingPathComponent("Items", isDirectory: true).path)
        else { throw BoardLibraryError.invalidPackage(package) }
    }

    private func inject(_ point: BoardLibraryFaultPoint) async throws {
        if faultInjection.consume(point) {
            throw BoardLibraryError.injectedFailure(point)
        }
    }
}
