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
    private let portablePackageService: BoardPortablePackageService
    private var faultInjection: BoardLibraryFaultInjection
    private var bootstrapTask: Task<LibraryState, Error>?
    /// Para onde vai o pacote de um mural excluído: o Lixo do Mac, para a pessoa poder recuperar.
    /// Os testes trocam por uma remoção simples, para não encher o Lixo de quem roda os testes.
    private let discardPackage: @Sendable (URL) throws -> Void
    /// A recuperação de trabalho interrompido roda uma vez por instância, na primeira listagem.
    private var didRecoverInterruptedWork = false

    public init(
        rootDirectory: URL = BoardStore.defaultDirectory(),
        faultInjection: BoardLibraryFaultInjection = .none,
        repositoryFaultInjection: BoardRepositoryFaultInjection = .none,
        packageLimits: BoardPackageLimits = BoardPackageLimits(),
        packageAvailableCapacity: @escaping @Sendable (URL) -> UInt64? = BoardPortablePackageService.defaultAvailableCapacity,
        discardPackage: @escaping @Sendable (URL) throws -> Void = BoardLibrary.moveToTrash
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
        self.portablePackageService = BoardPortablePackageService(
            limits: packageLimits,
            availableCapacity: packageAvailableCapacity)
        self.faultInjection = faultInjection
        self.bootstrapTask = nil
        self.discardPackage = discardPackage
    }

    /// Move o item para o Lixo do Mac.
    public static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
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

    public func lifecycleState() throws -> LibraryState? {
        try loadState()
    }

    /// Recupera trocas de pacote interrompidas e limpa restos antigos de Boards/, Drafts/, Transfers/ e ImportStaging/.
    /// Roda uma única vez por instância; falhas são registradas e nunca impedem a listagem.
    func recoverInterruptedWork(now: Date = .now) {
        guard !didRecoverInterruptedWork else { return }
        didRecoverInterruptedWork = true
        let recovery = InterruptedWorkRecovery(now: now, discard: discardPackage)
        recovery.recoverPackages(in: boardsDirectory)
        recovery.recoverPackages(in: draftsDirectory, packageName: "Welcome.mural")
        recovery.removeOldEntries(in: transfersDirectory)
        recovery.removeOldEntries(in: importStagingDirectory)
    }

    public func listSaved() async throws -> [BoardLibraryEntry] {
        try await listSavedReport().entries
    }

    /// Murais salvos e os packages que não puderam ser lidos. Um package danificado,
    /// com nome inesperado ou de uma versão mais nova é pulado e relatado; ele não
    /// pode esconder os outros murais. Só falhas da própria pasta `Boards/` lançam.
    public func listSavedReport() async throws -> BoardLibraryListing {
        try makeDirectories()
        recoverInterruptedWork()
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: boardsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw BoardLibraryError.io(String(describing: error))
        }
        var result: [BoardLibraryEntry] = []
        var unreadable: [BoardLibraryIssue] = []
        for package in entries where package.pathExtension == "mural" {
            let manifestURL = package.appendingPathComponent("manifest.json")
            guard FileManager.default.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let manifest = try decodeManifest(from: manifestURL)
                let expectedName = "\(manifest.id.rawValue.uuidString).mural"
                guard package.deletingLastPathComponent().standardizedFileURL == boardsDirectory.standardizedFileURL,
                    package.lastPathComponent == expectedName
                else {
                    throw BoardLibraryError.invalidPackage(package)
                }
                try validateCompletePackage(package)
                result.append(BoardLibraryEntry(manifest: manifest, route: .saved(manifest.id)))
            } catch {
                unreadable.append(
                    BoardLibraryIssue(packageName: package.lastPathComponent, reason: error.localizedDescription))
            }
        }
        let sorted = result.sorted {
            let nameOrder = $0.manifest.name.compare($1.manifest.name)
            return nameOrder == .orderedSame
                ? $0.manifest.id.rawValue.uuidString < $1.manifest.id.rawValue.uuidString
                : nameOrder == .orderedAscending
        }
        return BoardLibraryListing(
            entries: sorted,
            unreadable: unreadable.sorted { $0.packageName < $1.packageName })
    }

    public func list() async throws -> [BoardLibraryEntry] {
        try await listReport().entries
    }

    /// Murais salvos, o rascunho de exemplo (quando existe) e os packages ilegíveis.
    public func listReport() async throws -> BoardLibraryListing {
        let saved = try await listSavedReport()
        let state = try await bootstrap()
        guard state.lifecycle == .draft else { return saved }
        guard let result = try await draftRepository.load(state.stableWelcomeID) else {
            throw BoardLibraryError.unavailableRoute(.welcomeDraft(state.stableWelcomeID))
        }
        return BoardLibraryListing(
            entries: saved.entries
                + [BoardLibraryEntry(manifest: result.snapshot.manifest, route: .welcomeDraft(state.stableWelcomeID))],
            unreadable: saved.unreadable)
    }

    /// - Throws: `BoardLibraryError.invalidName` se o nome tiver o que o macOS não aceita num nome de arquivo; nada é criado.
    public func createNamedBoard(_ name: String) async throws -> BoardRoute {
        if let issue = BoardName.issue(in: name) { throw BoardLibraryError.invalidName(issue) }
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

    /// Cria o pacote de um mural que já tem identidade fora deste Mac, como o do iCloud trazido por convite ou vindo de outro Mac do
    /// dono: o `id` não pode mudar, senão a zona dele no iCloud deixaria de casar com o pacote. O mural nasce vazio e já com o `cloud`
    /// no manifesto (schema 2); o conteúdo e o nome verdadeiros chegam depois, pela sincronização.
    /// - Returns: a rota do mural novo, ou `nil`, sem tocar em nada, se já existe um pacote com esse `id`.
    public func createBoard(id: BoardID, name: String, cloud: BoardCloudInfo?) async throws -> BoardRoute? {
        _ = try await bootstrap()
        let package = await savedRepository.packageURL(for: id)
        guard !FileManager.default.fileExists(atPath: package.path) else { return nil }
        let snapshot = BoardRepositorySnapshot(
            manifest: BoardManifest(id: id, name: name, cloud: cloud),
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

    /// Lê o conteúdo de um mural sem abri-lo: só leitura, para a capa do painel da barra de menus. `open(_:)` pode
    /// pôr um view-state ilegível em quarentena; aqui só o `board.json` é lido. Não confere o estado do rascunho de
    /// exemplo, não cria pastas e não mexe no pacote.
    /// - Returns: `nil` para `.library` e para um pacote sem `board.json`.
    /// - Throws: os erros de `BoardRepository.readBoard(_:)`.
    public func readBoard(_ route: BoardRoute) async throws -> Board? {
        switch route {
        case .library:
            return nil
        case .welcomeDraft(let id):
            return try await draftRepository.readBoard(id)
        case .saved(let id):
            return try await savedRepository.readBoard(id)
        }
    }

    /// - Throws: `BoardLibraryError.invalidName` se o nome tiver o que o macOS não aceita num nome de arquivo; o nome não muda.
    public func rename(_ route: BoardRoute, to name: String) async throws -> BoardRoute {
        if let issue = BoardName.issue(in: name) { throw BoardLibraryError.invalidName(issue) }
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

    /// Exclui o mural da biblioteca. Um mural salvo vai para o Lixo do Mac; o rascunho de exemplo é
    /// descartado, como em `discardWelcomeDraft()`. Quem tem o mural aberto precisa fechá-lo antes: uma
    /// sessão viva recriaria o pacote na próxima gravação.
    public func deleteBoard(_ route: BoardRoute) async throws {
        switch route {
        case .library:
            throw BoardLibraryError.unavailableRoute(route)
        case .welcomeDraft(let id):
            guard let state = try loadState(), state.lifecycle == .draft, state.stableWelcomeID == id else {
                throw BoardLibraryError.unavailableRoute(route)
            }
            try await discardWelcomeDraft()
        case .saved(let id):
            let package = await savedRepository.packageURL(for: id)
            guard FileManager.default.fileExists(atPath: package.path) else {
                throw BoardLibraryError.unavailableRoute(route)
            }
            do {
                try discardPackage(package)
            } catch {
                throw BoardLibraryError.io(String(describing: error))
            }
        }
    }

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

    /// Exports a board as an isolated package under `Transfers`.
    public func exportPackage(_ route: BoardRoute) async throws -> URL {
        let source = try packageSource(for: route)
        try makeDirectories()
        return try await assemblePackage(from: source, in: transfersDirectory, named: "\(UUID().uuidString).mural")
    }

    /// Cópia de segurança completa do mural em `directory/<uuid>-<data>.mural`, a pasta criada se faltar.
    ///
    /// É a mesma montagem de `exportPackage`, mas o pacote fica onde está: serve de rede de segurança antes de o mural ser enviado
    /// ao iCloud pela primeira vez, e quem chama passa uma pasta própria (`Application Support/Mural/Backups/`). A data vem de
    /// `now` em UTC, sem separadores, para o nome servir em qualquer volume. Duas cópias do mesmo mural no mesmo segundo
    /// recusam a segunda (`BoardPortablePackageError.destinationExists`) em vez de sobrescrever a primeira.
    public func backupPackage(_ route: BoardRoute, to directory: URL, now: Date = .now) async throws -> URL {
        let source = try packageSource(for: route)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch { throw BoardLibraryError.io(String(describing: error)) }
        let stamp = now.formatted(
            .iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false).timeSeparator(.omitted)
                .timeZone(separator: .omitted))
        return try await assemblePackage(from: source, in: directory, named: "\(source.id.rawValue.uuidString)-\(stamp).mural")
    }

    private typealias PackageSource = (repository: BoardRepository, id: BoardID)

    /// O repositório e o id do mural de uma rota que pode virar pacote: um mural salvo, ou o rascunho de exemplo ainda vivo.
    private func packageSource(for route: BoardRoute) throws -> PackageSource {
        let repository = try repository(for: route)
        switch route {
        case .library:
            throw BoardLibraryError.unavailableRoute(route)
        case .welcomeDraft(let welcomeID):
            guard let state = try loadState(), state.lifecycle == .draft, state.stableWelcomeID == welcomeID else {
                throw BoardLibraryError.unavailableRoute(route)
            }
            return (repository, welcomeID)
        case .saved(let savedID):
            return (repository, savedID)
        }
    }

    /// Monta o pacote do mural numa pasta de passagem escondida dentro de `root` e só o publica como `name` depois de validado; a
    /// pasta de passagem sai de qualquer jeito.
    private func assemblePackage(from source: PackageSource, in root: URL, named name: String) async throws -> URL {
        let destination = root.appendingPathComponent(name, isDirectory: true)
        let staging = root.appendingPathComponent(".\(destination.lastPathComponent)-materializing", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try await source.repository.materializePackage(for: source.id, to: staging)
            return try await portablePackageService.finalize(package: staging, destination: destination, root: root)
        } catch let error as BoardPortablePackageError {
            throw BoardLibraryError.portable(error)
        } catch let error as BoardRepositoryError {
            throw error
        } catch {
            throw BoardLibraryError.io(String(describing: error))
        }
    }

    /// Removes a package previously returned by `exportPackage`.
    public func cleanupTransfer(_ package: URL) async throws {
        do {
            try await portablePackageService.cleanup(package, inside: transfersDirectory)
        } catch let error as BoardPortablePackageError {
            throw BoardLibraryError.portable(error)
        } catch {
            throw BoardLibraryError.io(String(describing: error))
        }
    }

    /// Imports an external package by copying it into staging before decoding.
    /// The source URL is never modified. A fresh board ID is always published.
    public func importPackage(from source: URL) async throws -> BoardRoute {
        try await importPackageWithReport(from: source).route
    }

    /// Imports a package and exposes workspace recovery status for diagnostics.
    public func importPackageWithReport(from source: URL) async throws -> BoardImportResult {
        try makeDirectories()
        let staging = importStagingDirectory.appendingPathComponent("\(UUID().uuidString).mural", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            let loaded = try await portablePackageService.copyAndRead(from: source, to: staging)
            let newID = BoardID()
            var manifest = loaded.snapshot.manifest
            manifest.id = newID
            // O mural importado é um mural novo, só deste Mac: não herda a zona do iCloud do mural de origem.
            manifest.cloud = nil
            // Mural novo recomeça as revisões: um valor no teto do inteiro travaria a primeira edição (`+= 1`).
            manifest.contentRevision = 0
            manifest.workspaceRevision = 0
            // O pacote pode vir de fora (outra build, outro programa) com um nome que o macOS não aceita num arquivo.
            if BoardName.issue(in: manifest.name) != nil { manifest.name = BoardName.sanitized(manifest.name) }
            var workspace = loaded.snapshot.workspace
            workspace.contentRevision = manifest.contentRevision
            let snapshot = BoardRepositorySnapshot(manifest: manifest, board: loaded.snapshot.board, workspace: workspace)
            try await savedRepository.save(
                snapshot,
                copyingItemsFrom: staging.appendingPathComponent("Items", isDirectory: true),
                preservingWorkspaceDiagnostic: loaded.workspaceDiagnostic
            )
            return BoardImportResult(boardID: newID, workspaceStatus: Self.portableWorkspaceStatus(loaded.workspaceStatus))
        } catch let error as BoardPortablePackageError {
            throw BoardLibraryError.portable(error)
        } catch let error as BoardRepositoryError {
            throw error
        } catch {
            throw BoardLibraryError.io(String(describing: error))
        }
    }

    private static func portableWorkspaceStatus(_ status: BoardWorkspaceLoadStatus) -> BoardPortableWorkspaceStatus {
        switch status {
        case .loaded: return .loaded
        case .missing: return .missing
        case .futureSchema(let version): return .futureSchema(version)
        case .quarantined(let filename): return .corrupted(filename)
        case .quarantineFailed(let message): return .corrupted(message)
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
