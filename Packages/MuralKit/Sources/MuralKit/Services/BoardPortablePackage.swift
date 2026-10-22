import Foundation

/// Limits used while validating a portable `.mural` package.
public struct BoardPackageLimits: Sendable, Equatable {
    public static let defaultManifestBytes: UInt64 = 1 * 1024 * 1024
    public static let defaultBoardBytes: UInt64 = 64 * 1024 * 1024
    public static let defaultMaximumItems = 10_000
    public static let defaultMaximumFileBytes: UInt64 = 20 * 1024 * 1024 * 1024

    public var manifestBytes: UInt64
    public var boardBytes: UInt64
    public var maximumItems: Int
    public var maximumFileBytes: UInt64
    public var maximumPackageBytes: UInt64

    public init(
        manifestBytes: UInt64 = Self.defaultManifestBytes,
        boardBytes: UInt64 = Self.defaultBoardBytes,
        maximumItems: Int = Self.defaultMaximumItems,
        maximumFileBytes: UInt64 = Self.defaultMaximumFileBytes,
        maximumPackageBytes: UInt64? = nil,
        availableCapacity: UInt64? = nil
    ) {
        self.manifestBytes = manifestBytes
        self.boardBytes = boardBytes
        self.maximumItems = maximumItems
        self.maximumFileBytes = maximumFileBytes
        let capacity = availableCapacity.map { min(Self.defaultMaximumFileBytes, Self.eightyPercent(of: $0)) }
        self.maximumPackageBytes = maximumPackageBytes ?? capacity ?? Self.defaultMaximumFileBytes
    }

    static func eightyPercent(of value: UInt64) -> UInt64 {
        (value / 5) * 4 + ((value % 5) * 4) / 5
    }
}

public enum BoardPortablePackageError: Error, Equatable, Sendable {
    case packageNotDirectory(URL)
    case unexpectedEntry(String)
    case symlink(URL)
    case nestedDirectory(URL)
    case fileTooLarge(URL, limit: UInt64)
    case packageTooLarge(limit: UInt64)
    case invalidManifest(String)
    case futureManifestSchema(Int)
    case invalidBoard(String)
    case futureBoardSchema(Int)
    case futureWorkspaceSchema(Int)
    case tooManyItems(limit: Int)
    case duplicateItemID(UUID)
    case invalidItemParent(UUID)
    case invalidItemPosition(UUID)
    case invalidFileName(UUID)
    case invalidReminder(UUID)
    case missingAsset(String)
    case duplicateAsset(String)
    case unreferencedAsset(String)
    case assetKindMismatch(UUID, expected: ItemKind, actual: ItemKind?)
    case notDescendant(URL)
    case destinationExists(URL)
    case io(String)
}

public enum BoardPortableWorkspaceStatus: Equatable, Sendable {
    case loaded
    case missing
    case corrupted(String)
    case futureSchema(Int)
}

/// Result of importing a package. The route is a newly-created saved board.
public struct BoardImportResult: Equatable, Sendable {
    public let boardID: BoardID
    public let workspaceStatus: BoardPortableWorkspaceStatus

    public init(boardID: BoardID, workspaceStatus: BoardPortableWorkspaceStatus) {
        self.boardID = boardID
        self.workspaceStatus = workspaceStatus
    }

    public var route: BoardRoute {
        .saved(boardID)
    }
}

struct BoardPortablePackageReadResult: Sendable {
    let snapshot: BoardRepositorySnapshot
    let workspaceStatus: BoardWorkspaceLoadStatus
    let workspaceIssues: [WorkspaceValidationIssue]
    let workspaceDiagnostic: Data?

    init(
        snapshot: BoardRepositorySnapshot,
        workspaceStatus: BoardWorkspaceLoadStatus,
        workspaceIssues: [WorkspaceValidationIssue] = [],
        workspaceDiagnostic: Data? = nil
    ) {
        self.snapshot = snapshot
        self.workspaceStatus = workspaceStatus
        self.workspaceIssues = workspaceIssues
        self.workspaceDiagnostic = workspaceDiagnostic
    }
}

/// Validates and copies complete portable packages without touching their source.
/// The actor is intentionally independent from the UI and from `@MainActor`.
public actor BoardPortablePackageService {
    public let limits: BoardPackageLimits
    private let fileManager: FileManager
    private let availableCapacity: @Sendable (URL) -> UInt64?

    public init(
        limits: BoardPackageLimits = BoardPackageLimits(),
        fileManager: FileManager = .default,
        availableCapacity: @escaping @Sendable (URL) -> UInt64? = BoardPortablePackageService.defaultAvailableCapacity
    ) {
        self.limits = limits
        self.fileManager = fileManager
        self.availableCapacity = availableCapacity
    }

    public func export(
        snapshot: BoardRepositorySnapshot,
        sourceItems: URL?,
        destination: URL
    ) throws -> URL {
        let root = destination.deletingLastPathComponent().standardizedFileURL
        let package = destination.standardizedFileURL
        try ensureDescendant(package, of: root)
        try ensurePathComponents(from: root, to: package)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".\(package.lastPathComponent)-staging-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let items = staging.appendingPathComponent("Items", isDirectory: true)
        try fileManager.createDirectory(at: items, withIntermediateDirectories: true)
        if let sourceItems {
            try copyTree(sourceItems.standardizedFileURL, to: items)
        }
        try encode(snapshot.manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
        try encode(snapshot.board).write(to: staging.appendingPathComponent("board.json"), options: .atomic)
        try encode(snapshot.workspace.validated(for: snapshot.board)).write(
            to: staging.appendingPathComponent("view-state.json"), options: .atomic)
        try validate(staging)
        return try finalize(package: staging, destination: package, root: root)
    }

    func finalize(package: URL, destination: URL, root: URL) throws -> URL {
        let package = package.standardizedFileURL
        let destination = destination.standardizedFileURL
        let root = root.standardizedFileURL
        try ensureDescendant(package, of: root)
        try ensureDescendant(destination, of: root)
        try ensurePathComponents(from: root, to: package)
        try ensurePathComponents(from: root, to: destination)
        try validate(package)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw BoardPortablePackageError.destinationExists(destination)
        }
        try fileManager.moveItem(at: package, to: destination)
        return destination
    }

    /// Copies a package into `staging`, validates it, and returns its decoded payload.
    /// The caller owns cleanup of the returned staging directory.
    func copyAndRead(from source: URL, to staging: URL) throws -> BoardPortablePackageReadResult {
        let source = source.standardizedFileURL
        let staging = staging.standardizedFileURL
        let packageLimit = effectivePackageLimit(for: staging.deletingLastPathComponent())
        try ensureNotSymlink(source)
        try preflight(source, packageLimit: packageLimit)
        guard !fileManager.fileExists(atPath: staging.path) else {
            throw BoardPortablePackageError.destinationExists(staging)
        }
        do {
            try copyTree(source, to: staging)
            return try read(staging, allowFutureWorkspace: true, packageLimit: packageLimit)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    public func validate(_ package: URL) throws {
        let package = package.standardizedFileURL
        _ = try read(package, allowFutureWorkspace: false, packageLimit: effectivePackageLimit(for: package))
    }

    func cleanup(_ package: URL, inside root: URL) throws {
        let package = package.standardizedFileURL
        let root = root.standardizedFileURL
        try ensureDescendant(package, of: root)
        try ensurePathComponents(from: root, to: package)
        guard fileManager.fileExists(atPath: package.path) else { return }
        try ensureNotSymlink(package)
        try fileManager.removeItem(at: package)
    }

    private func read(_ package: URL, allowFutureWorkspace: Bool, packageLimit: UInt64) throws -> BoardPortablePackageReadResult {
        let structure = try validateStructure(package)
        let manifestURL = structure.manifestURL
        let boardURL = structure.boardURL
        let itemsURL = structure.itemsURL
        try ensureNoSymlinksRecursively(package)
        try enforcePackageSize(package, limit: packageLimit)
        try ensureRegularFile(manifestURL)
        try ensureRegularFile(boardURL)
        let manifestData = try boundedData(at: manifestURL, limit: limits.manifestBytes)
        let boardData = try boundedData(at: boardURL, limit: limits.boardBytes)
        let manifest: BoardManifest
        do { manifest = try decode(BoardManifest.self, from: manifestData) } catch {
            throw BoardPortablePackageError.invalidManifest(String(describing: error))
        }
        guard manifest.schemaVersion <= BoardManifest.currentSchemaVersion else {
            throw BoardPortablePackageError.futureManifestSchema(manifest.schemaVersion)
        }
        let board: Board
        do { board = try decode(Board.self, from: boardData) } catch {
            throw BoardPortablePackageError.invalidBoard(String(describing: error))
        }
        guard board.formatVersion <= Board.currentFormatVersion else {
            throw BoardPortablePackageError.futureBoardSchema(board.formatVersion)
        }
        try validateBoard(board, itemsURL: itemsURL)

        let workspaceURL = package.appendingPathComponent("view-state.json")
        guard fileManager.fileExists(atPath: workspaceURL.path) else {
            let state = BoardWorkspaceState(contentRevision: manifest.contentRevision).canonicalized(for: board)
            return BoardPortablePackageReadResult(
                snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: state.state), workspaceStatus: .missing,
                workspaceIssues: state.issues)
        }
        try ensureRegularFile(workspaceURL)
        let rawWorkspaceData = try boundedData(at: workspaceURL, limit: limits.boardBytes)
        let workspace: BoardWorkspaceState
        do {
            workspace = try decode(BoardWorkspaceState.self, from: rawWorkspaceData)
        } catch {
            let state = BoardWorkspaceState(contentRevision: manifest.contentRevision).canonicalized(for: board)
            return BoardPortablePackageReadResult(
                snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: state.state),
                workspaceStatus: .quarantined(filename: workspaceURL.lastPathComponent), workspaceIssues: state.issues,
                workspaceDiagnostic: rawWorkspaceData)
        }
        guard workspace.schemaVersion <= BoardWorkspaceState.currentSchemaVersion else {
            if !allowFutureWorkspace {
                throw BoardPortablePackageError.futureWorkspaceSchema(workspace.schemaVersion)
            }
            let state = BoardWorkspaceState(contentRevision: manifest.contentRevision).canonicalized(for: board)
            return BoardPortablePackageReadResult(
                snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: state.state),
                workspaceStatus: .futureSchema(version: workspace.schemaVersion), workspaceIssues: state.issues,
                workspaceDiagnostic: rawWorkspaceData)
        }
        var canonical = workspace.canonicalized(for: board)
        if canonical.state.contentRevision != manifest.contentRevision {
            var state = canonical.state
            state.contentRevision = manifest.contentRevision
            canonical = WorkspaceValidationResult(state: state, issues: canonical.issues + [.contentRevisionAdjusted])
        }
        return BoardPortablePackageReadResult(
            snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: canonical.state), workspaceStatus: .loaded,
            workspaceIssues: canonical.issues)
    }

    private func validateStructure(_ package: URL) throws -> (manifestURL: URL, boardURL: URL, itemsURL: URL) {
        try ensureNotSymlink(package)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: package.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BoardPortablePackageError.packageNotDirectory(package)
        }
        let entries = try safeChildren(of: package)
        let allowed = Set(["manifest.json", "board.json", "view-state.json", "Items"])
        for entry in entries where !allowed.contains(entry.lastPathComponent) {
            throw BoardPortablePackageError.unexpectedEntry(entry.lastPathComponent)
        }
        let manifestURL = package.appendingPathComponent("manifest.json")
        let boardURL = package.appendingPathComponent("board.json")
        let itemsURL = package.appendingPathComponent("Items", isDirectory: true)
        guard fileManager.fileExists(atPath: manifestURL.path), fileManager.fileExists(atPath: boardURL.path),
            fileManager.fileExists(atPath: itemsURL.path)
        else {
            throw BoardPortablePackageError.unexpectedEntry("required entry missing")
        }
        var itemsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: itemsURL.path, isDirectory: &itemsDirectory), itemsDirectory.boolValue else {
            throw BoardPortablePackageError.unexpectedEntry("Items")
        }
        return (manifestURL, boardURL, itemsURL)
    }

    private func preflight(_ package: URL, packageLimit: UInt64) throws {
        let structure = try validateStructure(package)
        try ensureNoSymlinksRecursively(package)
        try enforcePackageSize(package, limit: packageLimit)
        let manifestData = try boundedData(at: structure.manifestURL, limit: limits.manifestBytes)
        let boardData = try boundedData(at: structure.boardURL, limit: limits.boardBytes)
        let manifest: BoardManifest
        do { manifest = try decode(BoardManifest.self, from: manifestData) } catch {
            throw BoardPortablePackageError.invalidManifest(String(describing: error))
        }
        guard manifest.schemaVersion <= BoardManifest.currentSchemaVersion else {
            throw BoardPortablePackageError.futureManifestSchema(manifest.schemaVersion)
        }
        let board: Board
        do { board = try decode(Board.self, from: boardData) } catch {
            throw BoardPortablePackageError.invalidBoard(String(describing: error))
        }
        guard board.formatVersion <= Board.currentFormatVersion else {
            throw BoardPortablePackageError.futureBoardSchema(board.formatVersion)
        }
        try validateBoard(board, itemsURL: structure.itemsURL)
        let workspaceURL = package.appendingPathComponent("view-state.json")
        if fileManager.fileExists(atPath: workspaceURL.path) {
            try ensureRegularFile(workspaceURL)
            _ = try boundedData(at: workspaceURL, limit: limits.boardBytes)
        }
    }

    func validateBoard(_ board: Board, itemsURL: URL) throws {
        guard board.items.count <= limits.maximumItems else { throw BoardPortablePackageError.tooManyItems(limit: limits.maximumItems) }
        var itemsByID: [UUID: BoardItem] = [:]
        for item in board.items {
            guard itemsByID.updateValue(item, forKey: item.id) == nil else {
                throw BoardPortablePackageError.duplicateItemID(item.id)
            }
            guard item.position.x.isFinite, item.position.y.isFinite else { throw BoardPortablePackageError.invalidItemPosition(item.id) }
        }
        var referenced = Set<String>()
        for item in board.items {
            if item.attachments != nil, item.kind != .text { throw BoardPortablePackageError.invalidFileName(item.id) }
            if item.parentID != nil {
                guard hasValidParentChain(item, in: itemsByID) else {
                    throw BoardPortablePackageError.invalidItemParent(item.id)
                }
            } else if item.kind == .folder, item.fileName != nil {
                throw BoardPortablePackageError.invalidFileName(item.id)
            }
            try validateReminder(of: item)
            if item.kind.storesFile {
                guard let fileName = item.fileName else {
                    throw BoardPortablePackageError.missingAsset("\(item.id.uuidString):fileName")
                }
                guard isSafeFileName(fileName) else { throw BoardPortablePackageError.invalidFileName(item.id) }
                guard referenced.insert(fileName).inserted else { throw BoardPortablePackageError.duplicateAsset(fileName) }
                let asset = itemsURL.appendingPathComponent(fileName)
                try ensureDescendant(asset, of: itemsURL)
                guard fileManager.fileExists(atPath: asset.path) else {
                    throw BoardPortablePackageError.missingAsset(fileName)
                }
                try ensureRegularFile(asset)
                let actualKind = ContentClassifier.kind(forFileAt: asset)
                guard actualKind == item.kind else {
                    throw BoardPortablePackageError.assetKindMismatch(item.id, expected: item.kind, actual: actualKind)
                }
                let size = try fileSize(asset)
                guard size <= limits.maximumFileBytes else {
                    throw BoardPortablePackageError.fileTooLarge(asset, limit: limits.maximumFileBytes)
                }
            } else if item.fileName != nil {
                throw BoardPortablePackageError.invalidFileName(item.id)
            }
        }
        let mediaNames = referenced
        for item in board.items {
            for attachment in item.attachments ?? [] {
                try validateAttachment(attachment, of: item, mediaNames: mediaNames, itemsURL: itemsURL)
                referenced.insert(attachment.fileName)
            }
        }
        // Nomes que o texto da nota cita e existem em `Items/` também são referenciados.
        for item in board.items where item.kind == .text {
            for name in item.assetFileNames where isSafeFileName(name) {
                if fileManager.fileExists(atPath: itemsURL.appendingPathComponent(name).path) { referenced.insert(name) }
            }
        }
        for asset in try safeChildren(of: itemsURL) {
            var directory: ObjCBool = false
            guard fileManager.fileExists(atPath: asset.path, isDirectory: &directory), !directory.boolValue else {
                throw BoardPortablePackageError.nestedDirectory(asset)
            }
            guard referenced.contains(asset.lastPathComponent) else {
                throw BoardPortablePackageError.unreferencedAsset(asset.lastPathComponent)
            }
        }
    }

    /// Cartão de lembrete leva o estado do lembrete e nenhum arquivo; os textos têm tamanho razoável.
    private func validateReminder(of item: BoardItem) throws {
        guard item.kind == .reminder else {
            if item.reminder != nil { throw BoardPortablePackageError.invalidReminder(item.id) }
            return
        }
        guard let reminder = item.reminder, item.fileName == nil,
            item.title.count <= 1_000, reminder.title.count <= 1_000, (reminder.notes?.count ?? 0) <= 100_000
        else { throw BoardPortablePackageError.invalidReminder(item.id) }
    }

    /// Um anexo de nota é uma imagem legível, com nome seguro, tamanho positivo e sem colidir com a mídia de um cartão.
    private func validateAttachment(
        _ attachment: NoteAttachment, of item: BoardItem, mediaNames: Set<String>, itemsURL: URL
    ) throws {
        let name = attachment.fileName
        guard NoteImageMarkup.isAttachmentName(name), attachment.pixelWidth > 0, attachment.pixelHeight > 0 else {
            throw BoardPortablePackageError.invalidFileName(item.id)
        }
        guard !mediaNames.contains(name) else { throw BoardPortablePackageError.duplicateAsset(name) }
        let asset = itemsURL.appendingPathComponent(name)
        try ensureDescendant(asset, of: itemsURL)
        guard fileManager.fileExists(atPath: asset.path) else { throw BoardPortablePackageError.missingAsset(name) }
        try ensureRegularFile(asset)
        guard ImageInspector.inspect(asset) != nil else {
            throw BoardPortablePackageError.assetKindMismatch(item.id, expected: .image, actual: nil)
        }
        guard try fileSize(asset) <= limits.maximumFileBytes else {
            throw BoardPortablePackageError.fileTooLarge(asset, limit: limits.maximumFileBytes)
        }
    }

    /// A cadeia de pais chega ao mural passando só por pastas e sem passar de `Board.maximumFolderDepth` níveis
    /// (uma pasta ocupa um nível; um cartão que não é pasta cabe em qualquer pasta). Um ciclo nunca chega ao mural
    /// e acaba no limite de níveis.
    private func hasValidParentChain(_ item: BoardItem, in itemsByID: [UUID: BoardItem]) -> Bool {
        var foldersAbove = 0
        var next = item.parentID
        while let parentID = next {
            guard let parent = itemsByID[parentID], parent.kind == .folder else { return false }
            foldersAbove += 1
            guard foldersAbove <= Board.maximumFolderDepth else { return false }
            next = parent.parentID
        }
        return item.kind != .folder || foldersAbove < Board.maximumFolderDepth
    }

    private func copyTree(_ source: URL, to destination: URL) throws {
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &directory) else {
            throw BoardPortablePackageError.packageNotDirectory(source)
        }
        try ensureNotSymlink(source)
        if directory.boolValue {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in try safeChildren(of: source) {
                try copyTree(child, to: destination.appendingPathComponent(child.lastPathComponent, isDirectory: false))
            }
        } else {
            try ensureRegularFile(source)
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func safeChildren(of directory: URL) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
    }

    private func ensureNoSymlinksRecursively(_ root: URL) throws {
        try ensureNotSymlink(root)
        var directory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else { return }
        for child in try safeChildren(of: root) { try ensureNoSymlinksRecursively(child) }
    }

    private func ensureRegularFile(_ url: URL) throws {
        try ensureNotSymlink(url)
        guard fileManager.fileExists(atPath: url.path) else {
            throw BoardPortablePackageError.unexpectedEntry(url.lastPathComponent)
        }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard (attributes[.type] as? FileAttributeType) == .typeRegular else {
            throw BoardPortablePackageError.unexpectedEntry(url.lastPathComponent)
        }
    }

    private func ensureNotSymlink(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        if (attributes[.type] as? FileAttributeType) == .typeSymbolicLink { throw BoardPortablePackageError.symlink(url) }
    }

    private func ensureDescendant(_ url: URL, of root: URL) throws {
        let child = url.standardizedFileURL.path
        let parent = root.standardizedFileURL.path
        guard child == parent || child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/") else {
            throw BoardPortablePackageError.notDescendant(url)
        }
    }

    private func ensurePathComponents(from root: URL, to url: URL) throws {
        let rootPath = root.standardizedFileURL.path
        let urlPath = url.standardizedFileURL.path
        guard urlPath == rootPath || urlPath.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/") else {
            throw BoardPortablePackageError.notDescendant(url)
        }
        var current = root.standardizedFileURL
        try ensureNotSymlink(current)
        let relative = String(urlPath.dropFirst(rootPath.count)).split(separator: "/", omittingEmptySubsequences: true)
        for component in relative {
            current.appendPathComponent(String(component))
            try ensureNotSymlink(current)
        }
    }

    private func boundedData(at url: URL, limit: UInt64) throws -> Data {
        let size = try fileSize(url)
        guard size <= limit else { throw BoardPortablePackageError.fileTooLarge(url, limit: limit) }
        return try Data(contentsOf: url)
    }

    private func fileSize(_ url: URL) throws -> UInt64 {
        let attrs = try fileManager.attributesOfItem(atPath: url.path)
        guard let number = attrs[.size] as? NSNumber else { throw BoardPortablePackageError.io("missing file size") }
        return number.uint64Value
    }

    private func enforcePackageSize(_ package: URL, limit: UInt64) throws {
        var total: UInt64 = 0
        var stack = [package]
        while let current = stack.popLast() {
            var directory: ObjCBool = false
            guard fileManager.fileExists(atPath: current.path, isDirectory: &directory) else { continue }
            if directory.boolValue {
                stack.append(contentsOf: try safeChildren(of: current))
            } else {
                let size = try fileSize(current)
                guard UInt64.max - total >= size else { throw BoardPortablePackageError.packageTooLarge(limit: limit) }
                total += size
                if total > limit { throw BoardPortablePackageError.packageTooLarge(limit: limit) }
            }
        }
    }

    private func effectivePackageLimit(for package: URL) -> UInt64 {
        let hardLimit = min(BoardPackageLimits.defaultMaximumFileBytes, limits.maximumPackageBytes)
        guard let capacity = availableCapacity(package) else { return hardLimit }
        return min(hardLimit, BoardPackageLimits.eightyPercent(of: capacity))
    }

    private func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
            && URL(fileURLWithPath: name).lastPathComponent == name
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
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

    public static func defaultAvailableCapacity(_ url: URL) -> UInt64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage.map(
            UInt64.init)
    }
}
