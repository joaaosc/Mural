import Foundation

/// Repositório isolado por mural. Todas as operações passam pelo mesmo actor e
/// nenhum caminho global ou "mural atual" participa da leitura ou gravação.
///
/// Um package existente é atualizado no lugar: a mídia em `Items/` é imutável e tem
/// nome único (o importador grava o arquivo antes de o board referenciá-lo, e a
/// exclusão só apaga o arquivo depois da gravação que deixou de referenciá-lo), então
/// só os JSON mudam. Cada JSON é substituído atomicamente e o `manifest.json` vai por
/// último, como marcador de commit. Packages novos (criação, promoção, importação,
/// migração) são montados em staging e publicados com uma renomeação.
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
    /// between reading JSON and copying its assets. Only the media and note attachments referenced by the
    /// board are copied: leftovers in `Items/` never reach (nor block) an export.
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
        let items = package.appendingPathComponent("Items", isDirectory: true)
        let sourceItems = packageURL(for: id).appendingPathComponent("Items", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        } catch {
            throw BoardRepositoryError.io(String(describing: error))
        }
        var required = Set<String>()
        var optional = Set<String>()
        for item in loaded.snapshot.board.items {
            required.formUnion(item.requiredAssetFileNames)
            optional.formUnion(item.assetFileNames)
        }
        // Nome só citado no texto da nota e ausente é ignorado: a nota mostra o texto alternativo.
        let referenced = required.union(
            optional.subtracting(required).filter {
                Self.isSafeAssetName($0)
                    && FileManager.default.fileExists(atPath: sourceItems.appendingPathComponent($0).path)
            })
        for name in referenced.sorted() {
            guard Self.isSafeAssetName(name) else { throw BoardRepositoryError.missingAsset(name) }
            let source = sourceItems.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else {
                throw BoardRepositoryError.missingAsset(name)
            }
            do {
                // Num volume APFS a cópia é um clone: não duplica os bytes.
                try FileManager.default.copyItem(at: source, to: items.appendingPathComponent(name))
            } catch {
                throw BoardRepositoryError.io(String(describing: error))
            }
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
        // Antes de qualquer outro arquivo ser tocado (o view-state ilegível é movido para quarentena
        // mais abaixo): uma build antiga não abre, e depois sobrescreveria, um mural de formato mais novo.
        guard board.formatVersion <= Board.currentFormatVersion else {
            throw BoardRepositoryError.futureBoardFormat(board.formatVersion)
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
        let signpost = MuralSignposts.persistence.beginInterval("Salvar mural")
        defer { MuralSignposts.persistence.endInterval("Salvar mural", signpost) }
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

        if sourceItems == nil, Self.isUpdatablePackage(package) {
            try await updateInPlace(
                package: package,
                manifest: manifest,
                existingManifest: existingManifest,
                board: snapshot.board,
                workspace: workspace,
                diagnostic: diagnostic)
        } else {
            try await publishPackage(
                id: id,
                package: package,
                manifest: manifest,
                board: snapshot.board,
                workspace: workspace,
                sourceItems: sourceItems,
                diagnostic: diagnostic)
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

    // MARK: Atualização no lugar

    /// Substitui só os JSON que mudaram, cada um de forma atômica, e o manifest por
    /// último. `Items/` não é copiada nem tocada. Em erro lançado, os arquivos já
    /// substituídos voltam ao conteúdo anterior a partir de hard links de backup.
    private func updateInPlace(
        package: URL,
        manifest: BoardManifest,
        existingManifest: BoardManifest?,
        board: Board,
        workspace: BoardWorkspaceState,
        diagnostic: Data?
    ) async throws {
        let fileManager = FileManager.default
        let boardURL = package.appendingPathComponent("board.json")
        let workspaceURL = package.appendingPathComponent("view-state.json")
        let manifestURL = package.appendingPathComponent("manifest.json")

        let boardData: Data
        let workspaceData: Data
        let manifestData: Data
        do {
            boardData = try encode(board)
            workspaceData = try encode(workspace)
            manifestData = try encode(manifest)
        } catch {
            throw BoardRepositoryError.io(String(describing: error))
        }

        let contentChanged = existingManifest.map { $0.contentRevision != manifest.contentRevision } ?? true
        let workspaceChanged = existingManifest.map { $0.workspaceRevision != manifest.workspaceRevision } ?? true
        var dataWrites: [(url: URL, data: Data)] = []
        if contentChanged || !fileManager.fileExists(atPath: boardURL.path) {
            dataWrites.append((boardURL, boardData))
        }
        // `contentRevision` também vive dentro do workspace.
        if contentChanged || workspaceChanged || !fileManager.fileExists(atPath: workspaceURL.path) {
            dataWrites.append((workspaceURL, workspaceData))
        }

        var transaction = InPlaceTransaction()
        defer { transaction.finish() }
        do {
            try fileManager.createDirectory(
                at: package.appendingPathComponent("Items", isDirectory: true),
                withIntermediateDirectories: true)
            try await inject(.beforeSwap)
            for write in dataWrites {
                try transaction.replace(write.url, with: write.data)
            }
            if let diagnostic {
                try transaction.create(
                    package.appendingPathComponent(".view-state-corrupt-\(UUID().uuidString).json"),
                    with: diagnostic)
            }
            try await inject(.afterSwap)
            try transaction.replace(manifestURL, with: manifestData)
            transaction.commit()
        } catch let error as BoardRepositoryError {
            throw error
        } catch {
            throw BoardRepositoryError.io(String(describing: error))
        }
    }

    /// Package existente que pode ser atualizado no lugar: diretório com `board.json`.
    private static func isUpdatablePackage(_ package: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: package.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return false }
        var boardIsDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: package.appendingPathComponent("board.json").path, isDirectory: &boardIsDirectory)
            && !boardIsDirectory.boolValue
    }

    // MARK: Publicação de package novo

    /// Monta o package em staging e o publica com uma renomeação. Se já houver algo no
    /// caminho (package incompleto), ele vai para um backup que só é apagado depois
    /// do sucesso; em qualquer erro o backup volta ao lugar e o que ocupava o caminho é
    /// guardado à parte, nunca apagado.
    private func publishPackage(
        id: BoardID,
        package: URL,
        manifest: BoardManifest,
        board: Board,
        workspace: BoardWorkspaceState,
        sourceItems: URL?,
        diagnostic: Data?
    ) async throws {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        } catch {
            throw BoardRepositoryError.io(String(describing: error))
        }

        let staging = rootDirectory.appendingPathComponent(
            ".\(id.rawValue.uuidString).mural-staging-\(UUID().uuidString)", isDirectory: true)
        let backup = rootDirectory.appendingPathComponent(
            ".\(id.rawValue.uuidString).mural-backup-\(UUID().uuidString)", isDirectory: true)
        var movedToBackup = false
        var didSwap = false
        var committed = false
        defer {
            if fileManager.fileExists(atPath: staging.path) { try? fileManager.removeItem(at: staging) }
            if movedToBackup, fileManager.fileExists(atPath: backup.path) {
                if committed {
                    try? fileManager.removeItem(at: backup)
                } else {
                    if fileManager.fileExists(atPath: package.path) {
                        // Algo recriou o caminho no meio da troca: guarda à parte, nunca apaga.
                        let intruder = rootDirectory.appendingPathComponent(
                            ".\(id.rawValue.uuidString).mural-intruder-\(UUID().uuidString)", isDirectory: true)
                        try? fileManager.moveItem(at: package, to: intruder)
                    }
                    try? fileManager.moveItem(at: backup, to: package)
                }
            }
        }
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            let items = staging.appendingPathComponent("Items", isDirectory: true)
            try fileManager.createDirectory(at: items, withIntermediateDirectories: true)
            let oldItems = package.appendingPathComponent("Items", isDirectory: true)
            let itemsSource = sourceItems ?? oldItems
            if fileManager.fileExists(atPath: itemsSource.path) {
                try fileManager.removeItem(at: items)
                try fileManager.copyItem(at: itemsSource, to: items)
            }
            try copyKnownDiagnostics(from: package, to: staging)
            if let diagnostic {
                let diagnosticURL = staging.appendingPathComponent(".view-state-corrupt-\(UUID().uuidString).json")
                try diagnostic.write(to: diagnosticURL, options: .atomic)
            }
            try encode(manifest).write(to: staging.appendingPathComponent("manifest.json"), options: .atomic)
            try encode(board).write(to: staging.appendingPathComponent("board.json"), options: .atomic)
            try encode(workspace).write(to: staging.appendingPathComponent("view-state.json"), options: .atomic)

            try await inject(.beforeSwap)
            if fileManager.fileExists(atPath: package.path) {
                try fileManager.moveItem(at: package, to: backup)
                movedToBackup = true
            }
            injectIntruderIfRequested(at: package)
            try fileManager.moveItem(at: staging, to: package)
            didSwap = true
            try await inject(.afterSwap)
            committed = true
        } catch let error as BoardRepositoryError {
            if didSwap, !committed { try? fileManager.removeItem(at: package) }
            throw error
        } catch {
            if didSwap, !committed { try? fileManager.removeItem(at: package) }
            throw BoardRepositoryError.io(String(describing: error))
        }
    }

    // MARK: Interno

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

    /// Só para testes: recria o caminho do package como faria um importador concorrente.
    private func injectIntruderIfRequested(at package: URL) {
        guard faultInjection.consume(.intruderBeforeMove) else { return }
        try? FileManager.default.createDirectory(
            at: package.appendingPathComponent("Items", isDirectory: true),
            withIntermediateDirectories: true)
    }

    /// Nome de arquivo de mídia aceito: um único componente, sem ocultos nem `..`.
    static func isSafeAssetName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
            && name == (name as NSString).lastPathComponent
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

/// Substituições atômicas de arquivos dentro de um package, com desfazer.
///
/// Antes de substituir um arquivo existente, cria um hard link de backup (custo
/// constante, sem copiar bytes). `finish()` desfaz tudo se `commit()` não foi chamado e
/// sempre apaga os backups.
private struct InPlaceTransaction {
    private var replaced: [(original: URL, backup: URL)] = []
    private var created: [URL] = []
    private var committed = false

    mutating func replace(_ url: URL, with data: Data) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).backup-\(UUID().uuidString)")
            try fileManager.linkItem(at: url, to: backup)
            replaced.append((url, backup))
        } else {
            created.append(url)
        }
        try data.write(to: url, options: .atomic)
    }

    mutating func create(_ url: URL, with data: Data) throws {
        created.append(url)
        try data.write(to: url, options: .atomic)
    }

    mutating func commit() {
        committed = true
    }

    func finish() {
        let fileManager = FileManager.default
        if !committed {
            for entry in replaced.reversed() where fileManager.fileExists(atPath: entry.backup.path) {
                // A troca atômica devolve o conteúdo anterior sem deixar o caminho vazio.
                _ = try? fileManager.replaceItemAt(entry.original, withItemAt: entry.backup)
            }
            for url in created.reversed() {
                try? fileManager.removeItem(at: url)
            }
        }
        for entry in replaced where fileManager.fileExists(atPath: entry.backup.path) {
            try? fileManager.removeItem(at: entry.backup)
        }
    }
}
