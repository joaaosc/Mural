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
    case tooManyFreeTexts(limit: Int)
    case textTooLarge(UUID)
    case duplicateItemID(UUID)
    case invalidItemParent(UUID)
    case invalidItemPosition(UUID)
    case invalidFileName(UUID)
    case invalidReminder(UUID)
    case invalidMusic(UUID)
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
    /// Nomes dos arquivos válidos de `Previews/` (citados por algum cartão e dentro dos limites), em ordem. Vazio sem a pasta.
    let previewNames: [String]

    init(
        snapshot: BoardRepositorySnapshot,
        workspaceStatus: BoardWorkspaceLoadStatus,
        workspaceIssues: [WorkspaceValidationIssue] = [],
        workspaceDiagnostic: Data? = nil,
        previewNames: [String] = []
    ) {
        self.previewNames = previewNames
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
    /// A leitura é coordenada: o sistema baixa o que está só no iCloud e espera o pacote ficar inteiro antes de entregá-lo.
    func copyAndRead(from source: URL, to staging: URL) throws -> BoardPortablePackageReadResult {
        let source = source.standardizedFileURL
        let staging = staging.standardizedFileURL
        let packageLimit = effectivePackageLimit(for: staging.deletingLastPathComponent())
        try ensureNotSymlink(source)
        var coordinationError: NSError?
        var outcome: Result<BoardPortablePackageReadResult, any Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: source, options: [.withoutChanges], error: &coordinationError
        ) { coordinated in
            outcome = Result { try copyPreflightedPackage(from: coordinated, to: staging, packageLimit: packageLimit) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw BoardPortablePackageError.io("coordinated read did not run") }
        return try outcome.get()
    }

    private func copyPreflightedPackage(
        from source: URL, to staging: URL, packageLimit: UInt64
    ) throws -> BoardPortablePackageReadResult {
        try preflight(source, packageLimit: packageLimit)
        guard !fileManager.fileExists(atPath: staging.path) else {
            throw BoardPortablePackageError.destinationExists(staging)
        }
        do {
            try copyTree(source, to: staging, isPackageRoot: true)
            return try read(staging, allowFutureWorkspace: true, packageLimit: packageLimit, forImport: true)
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

    /// `forImport` liga as recusas e normalizações que valem só para pacotes vindos de fora; exportação, cópia do iCloud Drive e
    /// backup usam o modo normal, que nunca é mais rígido do que era.
    private func read(
        _ package: URL, allowFutureWorkspace: Bool, packageLimit: UInt64, forImport: Bool = false
    ) throws -> BoardPortablePackageReadResult {
        let structure = try validateStructure(package)
        let manifestURL = structure.manifestURL
        let boardURL = structure.boardURL
        let itemsURL = structure.itemsURL
        try ensureNoSymlinksRecursively(package, isPackageRoot: true)
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
        try validateBoard(board, itemsURL: itemsURL, forImport: forImport)
        let previewNames = try validatePreviews(in: package, board: board, forImport: forImport)

        let workspaceURL = package.appendingPathComponent("view-state.json")
        guard fileManager.fileExists(atPath: workspaceURL.path) else {
            let state = BoardWorkspaceState(contentRevision: manifest.contentRevision).canonicalized(for: board)
            return BoardPortablePackageReadResult(
                snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: state.state), workspaceStatus: .missing,
                workspaceIssues: state.issues, previewNames: previewNames)
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
                workspaceDiagnostic: rawWorkspaceData, previewNames: previewNames)
        }
        guard workspace.schemaVersion <= BoardWorkspaceState.currentSchemaVersion else {
            if !allowFutureWorkspace {
                throw BoardPortablePackageError.futureWorkspaceSchema(workspace.schemaVersion)
            }
            let state = BoardWorkspaceState(contentRevision: manifest.contentRevision).canonicalized(for: board)
            return BoardPortablePackageReadResult(
                snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: state.state),
                workspaceStatus: .futureSchema(version: workspace.schemaVersion), workspaceIssues: state.issues,
                workspaceDiagnostic: rawWorkspaceData, previewNames: previewNames)
        }
        var canonical = workspace.canonicalized(for: board)
        if canonical.state.contentRevision != manifest.contentRevision {
            var state = canonical.state
            state.contentRevision = manifest.contentRevision
            canonical = WorkspaceValidationResult(state: state, issues: canonical.issues + [.contentRevisionAdjusted])
        }
        return BoardPortablePackageReadResult(
            snapshot: BoardRepositorySnapshot(manifest: manifest, board: board, workspace: canonical.state), workspaceStatus: .loaded,
            workspaceIssues: canonical.issues, previewNames: previewNames)
    }

    /// Confere `Previews/`, a pasta das imagens de prévia de link e de capa de música de uma cópia para outras pessoas. Cada
    /// arquivo precisa ter nome seguro, ser comum, caber em `LinkPreviewFiles.maximumEmbeddedBytes`, ser uma imagem legível dentro
    /// do limite de pixels e ser citado por algum cartão. Na exportação, qualquer falha recusa o pacote (a própria exportação só
    /// grava o que passa); na importação, o arquivo que não passa é ignorado e o cartão busca de novo quando a pessoa permitir.
    /// Devolve os nomes aceitos.
    private func validatePreviews(in package: URL, board: Board, forImport: Bool) throws -> [String] {
        let directory = package.appendingPathComponent("Previews", isDirectory: true)
        switch try entryKind(directory) {
        case .missing: return []
        case .directory: break
        case .symlink: throw BoardPortablePackageError.symlink(directory)
        case .regular, .other:
            if forImport { return [] }
            throw BoardPortablePackageError.unexpectedEntry("Previews")
        }
        var cited = Set<String>()
        for item in board.items {
            cited.formUnion([item.link?.previewImageFile, item.link?.iconFile, item.music?.artworkFile].compactMap { $0 })
        }
        var accepted: [String] = []
        for entry in try safeChildren(of: directory).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            let problem: BoardPortablePackageError?
            if try entryKind(entry) != .regular {
                problem = .unexpectedEntry("Previews/\(name)")
            } else if !LinkPreviewFiles.isSafeFileName(name) {
                problem = .unexpectedEntry("Previews/\(name)")
            } else if !cited.contains(name) {
                problem = .unreferencedAsset("Previews/\(name)")
            } else if try fileSize(entry) > UInt64(LinkPreviewFiles.maximumEmbeddedBytes) {
                problem = .fileTooLarge(entry, limit: UInt64(LinkPreviewFiles.maximumEmbeddedBytes))
            } else if !LinkPreviewFiles.isEmbeddable(at: entry) {
                problem = .unexpectedEntry("Previews/\(name)")
            } else {
                problem = nil
            }
            if let problem {
                if forImport { continue }
                throw problem
            }
            accepted.append(name)
        }
        return accepted
    }

    private func validateStructure(_ package: URL) throws -> (manifestURL: URL, boardURL: URL, itemsURL: URL) {
        guard try entryKind(package) == .directory else {
            try ensureNotSymlink(package)
            throw BoardPortablePackageError.packageNotDirectory(package)
        }
        let allowed = Set(["manifest.json", "board.json", "view-state.json", "Items", "Previews"])
        for entry in try safeChildren(of: package, isPackageRoot: true) where !allowed.contains(entry.lastPathComponent) {
            throw BoardPortablePackageError.unexpectedEntry(entry.lastPathComponent)
        }
        let manifestURL = package.appendingPathComponent("manifest.json")
        let boardURL = package.appendingPathComponent("board.json")
        let itemsURL = package.appendingPathComponent("Items", isDirectory: true)
        guard try entryKind(manifestURL) != .missing, try entryKind(boardURL) != .missing, try entryKind(itemsURL) != .missing else {
            throw BoardPortablePackageError.unexpectedEntry("required entry missing")
        }
        guard try entryKind(itemsURL) == .directory else {
            try ensureNotSymlink(itemsURL)
            throw BoardPortablePackageError.unexpectedEntry("Items")
        }
        return (manifestURL, boardURL, itemsURL)
    }

    /// Triagem barata antes de copiar: estrutura, atalhos, tamanho, decodificação, versões e contagens. A conferência completa
    /// (mídia, anexos e imagens) roda uma vez só, sobre a cópia.
    private func preflight(_ package: URL, packageLimit: UInt64) throws {
        let structure = try validateStructure(package)
        try ensureNoSymlinksRecursively(package, isPackageRoot: true)
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
        guard board.items.count <= limits.maximumItems else { throw BoardPortablePackageError.tooManyItems(limit: limits.maximumItems) }
        guard board.freeTexts.count <= BoardImportNormalizer.maximumFreeTexts else {
            throw BoardPortablePackageError.tooManyFreeTexts(limit: BoardImportNormalizer.maximumFreeTexts)
        }
        let workspaceURL = package.appendingPathComponent("view-state.json")
        if try entryKind(workspaceURL) != .missing {
            try ensureRegularFile(workspaceURL)
            _ = try boundedData(at: workspaceURL, limit: limits.boardBytes)
        }
    }

    /// Em `forImport`, nomes citados pelo mural que começam com "." são inválidos (como já são para o mural interno) e as
    /// dimensões dos anexos não são conferidas aqui, porque a normalização as relê do arquivo.
    func validateBoard(_ board: Board, itemsURL: URL, forImport: Bool = false) throws {
        guard board.items.count <= limits.maximumItems else { throw BoardPortablePackageError.tooManyItems(limit: limits.maximumItems) }
        var itemsByID: [UUID: BoardItem] = [:]
        for item in board.items {
            guard itemsByID.updateValue(item, forKey: item.id) == nil else {
                throw BoardPortablePackageError.duplicateItemID(item.id)
            }
            guard item.position.x.isFinite, item.position.y.isFinite else { throw BoardPortablePackageError.invalidItemPosition(item.id) }
            if let place = item.folderPosition {
                guard place.x.isFinite, place.y.isFinite else { throw BoardPortablePackageError.invalidItemPosition(item.id) }
            }
        }
        var referenced = Set<String>()
        for item in board.items {
            if item.attachments != nil, item.kind != .text { throw BoardPortablePackageError.invalidFileName(item.id) }
            if item.parentID != nil {
                guard Board.hasValidParentChain(item, in: itemsByID) else {
                    throw BoardPortablePackageError.invalidItemParent(item.id)
                }
            } else if item.kind == .folder, item.fileName != nil {
                throw BoardPortablePackageError.invalidFileName(item.id)
            }
            try validateReminder(of: item)
            try validateMusic(of: item, forImport: forImport)
            if item.kind.storesFile {
                guard let fileName = item.fileName else {
                    throw BoardPortablePackageError.missingAsset("\(item.id.uuidString):fileName")
                }
                guard isSafeFileName(fileName, forImport: forImport) else { throw BoardPortablePackageError.invalidFileName(item.id) }
                guard referenced.insert(fileName).inserted else { throw BoardPortablePackageError.duplicateAsset(fileName) }
                let asset = itemsURL.appendingPathComponent(fileName)
                try ensureDescendant(asset, of: itemsURL)
                try ensureAssetExists(asset, named: fileName)
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
                try validateAttachment(attachment, of: item, mediaNames: mediaNames, itemsURL: itemsURL, forImport: forImport)
                referenced.insert(attachment.fileName)
            }
        }
        // Nomes que o texto da nota cita e existem em `Items/` também são referenciados.
        for item in board.items where item.kind == .text {
            for name in item.assetFileNames where isSafeFileName(name, forImport: forImport) {
                if try entryKind(itemsURL.appendingPathComponent(name)) != .missing { referenced.insert(name) }
            }
        }
        for asset in try safeChildren(of: itemsURL) {
            guard try entryKind(asset) != .directory else {
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

    /// Um cartão de música guarda só o estado, sem arquivo de mídia; a capa não viaja no pacote.
    private func validateMusic(of item: BoardItem, forImport: Bool) throws {
        guard item.kind == .music else {
            if item.music != nil { throw BoardPortablePackageError.invalidMusic(item.id) }
            return
        }
        guard let music = item.music, item.fileName == nil,
            item.title.count <= 1_000, music.title.count <= 1_000,
            (music.subtitle?.count ?? 0) <= 1_000, (music.albumTitle?.count ?? 0) <= 1_000,
            (music.libraryPlaylistName?.count ?? 0) <= 1_000,
            music.artworkFile.map({ isSafeFileName($0, forImport: forImport) }) ?? true,
            // Valores absurdos viriam de um pacote adulterado e travariam a exibição.
            music.duration.map({ $0.isFinite && $0 >= 0 && $0 <= 10_000_000 }) ?? true,
            music.trackCount.map({ (0...100_000).contains($0) }) ?? true
        else { throw BoardPortablePackageError.invalidMusic(item.id) }
    }

    /// Um anexo de nota é uma imagem legível, com nome seguro, tamanho positivo e sem colidir com a mídia de um cartão.
    private func validateAttachment(
        _ attachment: NoteAttachment, of item: BoardItem, mediaNames: Set<String>, itemsURL: URL, forImport: Bool
    ) throws {
        let name = attachment.fileName
        // Na importação as dimensões são relidas do arquivo depois; o que o pacote declara não conta.
        let validSize = forImport || (attachment.pixelWidth > 0 && attachment.pixelHeight > 0)
        guard NoteImageMarkup.isAttachmentName(name), validSize else {
            throw BoardPortablePackageError.invalidFileName(item.id)
        }
        guard !mediaNames.contains(name) else { throw BoardPortablePackageError.duplicateAsset(name) }
        let asset = itemsURL.appendingPathComponent(name)
        try ensureDescendant(asset, of: itemsURL)
        try ensureAssetExists(asset, named: name)
        try ensureRegularFile(asset)
        guard ImageInspector.inspect(asset) != nil else {
            throw BoardPortablePackageError.assetKindMismatch(item.id, expected: .image, actual: nil)
        }
        guard try fileSize(asset) <= limits.maximumFileBytes else {
            throw BoardPortablePackageError.fileTooLarge(asset, limit: limits.maximumFileBytes)
        }
    }

    /// Falta de arquivo é `missingAsset`; atalho (inclusive quebrado) é recusado como atalho.
    private func ensureAssetExists(_ asset: URL, named name: String) throws {
        switch try entryKind(asset) {
        case .missing: throw BoardPortablePackageError.missingAsset(name)
        case .symlink: throw BoardPortablePackageError.symlink(asset)
        case .directory, .regular, .other: return
        }
    }

    /// Nomes escondidos (`.DS_Store`, `._foto.png`, `Icon\r`) são criados pelo Finder e por volumes exFAT/SMB; `QuickLook` na
    /// raiz é reservado para uma miniatura futura. Nada disso faz parte do pacote: não conta e não é copiado.
    private func isIgnoredEntry(_ name: String, isPackageRoot: Bool) -> Bool {
        name.hasPrefix(".") || name == "Icon\r" || (isPackageRoot && name == "QuickLook")
    }

    private func copyTree(_ source: URL, to destination: URL, isPackageRoot: Bool = false) throws {
        switch try entryKind(source) {
        case .missing:
            throw BoardPortablePackageError.packageNotDirectory(source)
        case .symlink:
            throw BoardPortablePackageError.symlink(source)
        case .directory:
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in try safeChildren(of: source, isPackageRoot: isPackageRoot) {
                try copyTree(child, to: destination.appendingPathComponent(child.lastPathComponent, isDirectory: false))
            }
        case .regular, .other:
            try ensureRegularFile(source)
            try fileManager.copyItem(at: source, to: destination)
        }
    }

    private func safeChildren(of directory: URL, isPackageRoot: Bool = false) throws -> [URL] {
        try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
            .filter { !isIgnoredEntry($0.lastPathComponent, isPackageRoot: isPackageRoot) }
    }

    private func ensureNoSymlinksRecursively(_ root: URL, isPackageRoot: Bool = false) throws {
        switch try entryKind(root) {
        case .symlink: throw BoardPortablePackageError.symlink(root)
        case .directory:
            for child in try safeChildren(of: root, isPackageRoot: isPackageRoot) { try ensureNoSymlinksRecursively(child) }
        case .missing, .regular, .other: return
        }
    }

    private func ensureRegularFile(_ url: URL) throws {
        switch try entryKind(url) {
        case .regular: return
        case .symlink: throw BoardPortablePackageError.symlink(url)
        case .missing, .directory, .other: throw BoardPortablePackageError.unexpectedEntry(url.lastPathComponent)
        }
    }

    private func ensureNotSymlink(_ url: URL) throws {
        if try entryKind(url) == .symlink { throw BoardPortablePackageError.symlink(url) }
    }

    private enum EntryKind { case missing, symlink, directory, regular, other }

    /// Classifica a entrada sem seguir atalhos, o que também pega atalho quebrado (que `fileExists` daria como inexistente).
    private func entryKind(_ url: URL) throws -> EntryKind {
        // O `URL` guarda valores em cache; um novo evita ler o estado de antes de uma troca.
        let fresh = URL(fileURLWithPath: url.path)
        do {
            let values = try fresh.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true { return .symlink }
            if values.isDirectory == true { return .directory }
            if values.isRegularFile == true { return .regular }
            return .other
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code)
        {
            return .missing
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return .missing
        }
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
        var stack = [(url: package, isPackageRoot: true)]
        while let (current, isPackageRoot) = stack.popLast() {
            switch try entryKind(current) {
            case .missing: continue
            case .directory:
                stack.append(contentsOf: try safeChildren(of: current, isPackageRoot: isPackageRoot).map { ($0, false) })
            case .symlink, .regular, .other:
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

    /// Na importação o nome citado também não pode começar com ".", igual a `BoardRepository.isSafeAssetName`: um mural que cita
    /// `.x.png` importaria, mas nunca exportaria.
    private func isSafeFileName(_ name: String, forImport: Bool = false) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
            && !(forImport && name.hasPrefix(".")) && URL(fileURLWithPath: name).lastPathComponent == name
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
