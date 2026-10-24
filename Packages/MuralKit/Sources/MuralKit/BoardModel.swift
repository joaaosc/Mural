import Foundation
import Observation
import StretchText

/// Estado vivo do mural: carrega do disco, aplica mudanças e grava após cada uma.
///
/// Fica no pacote de domínio para ser testado sem interface; a interface só
/// observa `board` e chama os métodos de alteração.
@MainActor
@Observable
public final class BoardModel {
    private static let derivedCacheEntryLimit = 16

    public enum Persistence: Sendable, Equatable {
        case immediate
        case deferred
    }

    public internal(set) var board: Board {
        didSet {
            boardRevision &+= 1
            rootItemsCache = nil
            freeTextsCache = nil
            rootItemSizesCache = nil
            freeTextSizesCache = nil
            reminderItemsCache = nil
            musicItemsCache = nil
            rootExtentCache = nil
            itemIndexCache = nil
            freeTextIndexCache = nil
            folderChildrenByParentCache = nil
            childrenCache.removeAll(keepingCapacity: true)
            childrenCacheOrder.removeAll(keepingCapacity: true)
            folderDestinationsCache.removeAll(keepingCapacity: true)
            folderDestinationsCacheOrder.removeAll(keepingCapacity: true)
            nonFolderFolderDestinationsCache.removeAll(keepingCapacity: true)
            nonFolderFolderDestinationsCacheOrder.removeAll(keepingCapacity: true)
        }
    }
    /// Revisão monotônica do valor do board, para consumidores que precisam reagir a qualquer mutação
    /// sem comparar estruturalmente todos os cartões e anexos.
    public private(set) var boardRevision: UInt64 = 0
    /// Última falha a mostrar ao usuário (importação, gravação, arquivo corrompido).
    public var lastError: String?
    /// Verdadeiro quando o mural salvo não pôde ser lido nem guardado à parte: nada é
    /// gravado, para não sobrescrever o arquivo original com um mural novo.
    public private(set) var isPersistenceSuspended = false

    @ObservationIgnored let store: BoardStore
    @ObservationIgnored let importer: ItemImporter
    @ObservationIgnored let persistence: Persistence
    @ObservationIgnored private var deferredDeletions: Set<String> = []
    @ObservationIgnored private var rootItemsCache: [BoardItem]?
    @ObservationIgnored private var freeTextsCache: [BoardFreeText]?
    @ObservationIgnored private var rootItemSizesCache: [UUID: BoardSize]?
    @ObservationIgnored private var freeTextSizesCache: [UUID: BoardSize]?
    @ObservationIgnored private var reminderItemsCache: [BoardItem]?
    @ObservationIgnored var musicItemsCache: [BoardItem]?
    @ObservationIgnored private var rootExtentCache: BoardSize?
    @ObservationIgnored private var itemIndexCache: [UUID: Int]?
    @ObservationIgnored private var freeTextIndexCache: [UUID: Int]?
    @ObservationIgnored private var folderChildrenByParentCache: [UUID: [BoardItem]]?
    @ObservationIgnored private var childrenCache: [UUID: [BoardItem]] = [:]
    @ObservationIgnored private var childrenCacheOrder: [UUID] = []
    @ObservationIgnored private var folderDestinationsCache: [UUID: [FolderDestination]] = [:]
    @ObservationIgnored private var folderDestinationsCacheOrder: [UUID] = []
    /// Cartões que não são pastas só diferem no destino pela pasta pai; agrupa esses resultados sem
    /// multiplicar uma lista de destinos grande por cartão.
    @ObservationIgnored private var nonFolderFolderDestinationsCache: [UUID?: [FolderDestination]] = [:]
    @ObservationIgnored private var nonFolderFolderDestinationsCacheOrder: [UUID?] = []

    /// - Parameter seedIfEmpty: na primeira abertura, começa com o mural de exemplo.
    public init(store: BoardStore, seedIfEmpty: Bool = true, persistence: Persistence = .immediate) {
        self.store = store
        self.importer = ItemImporter(itemsDirectory: store.itemsDirectory)
        self.persistence = persistence
        let empty = seedIfEmpty ? SampleBoard.make() : Board()
        do {
            if let loaded = try store.load() {
                board = loaded
            } else {
                board = empty
                persist()
            }
        } catch BoardStoreError.corruptedFile {
            board = empty
            do {
                let moved = try store.quarantineCorruptedFile()
                lastError = "O mural salvo estava ilegível e foi guardado como \(moved.lastPathComponent). Um mural novo foi criado."
                persist()
            } catch {
                isPersistenceSuspended = true
                lastError = "O mural salvo está ilegível e não pôde ser guardado à parte. Nada será gravado até isso ser resolvido."
            }
        } catch {
            board = empty
            isPersistenceSuspended = true
            lastError = "Não foi possível abrir o mural salvo (\(error.localizedDescription)). Nada será gravado para não sobrescrevê-lo."
        }
    }

    /// Creates a UI adapter from a snapshot already loaded by a `BoardSession`.
    /// Deferred persistence lets the session own revisions and atomic flushes.
    public init(board: Board, store: BoardStore, persistence: Persistence = .immediate) {
        self.store = store
        self.importer = ItemImporter(itemsDirectory: store.itemsDirectory)
        self.persistence = persistence
        self.board = board
    }

    // MARK: Leitura

    public var rootItems: [BoardItem] {
        let currentBoard = board
        if let rootItemsCache { return rootItemsCache }
        let rootItems = currentBoard.rootItems
        rootItemsCache = rootItems
        return rootItems
    }

    public var freeTexts: [BoardFreeText] {
        let currentBoard = board
        if let freeTextsCache { return freeTextsCache }
        let freeTexts = currentBoard.freeTexts
        freeTextsCache = freeTexts
        return freeTexts
    }

    /// Tamanhos dos cartões soltos, memoizados enquanto o `board` não muda.
    /// O canvas consulta o mapa em várias recomposições durante rolagem e zoom;
    /// manter o derivado junto ao modelo evita repetir `BoardLayout.size(of:)` em
    /// cada ciclo sem carregar dimensões entre revisões diferentes.
    public var rootItemSizes: [UUID: BoardSize] {
        let currentBoard = board
        if let rootItemSizesCache { return rootItemSizesCache }
        let sizes = Dictionary(
            uniqueKeysWithValues: currentBoard.rootItems.map { item in
                let size = BoardLayout.size(of: item)
                return (item.id, BoardSize(width: size.width, height: size.height))
            })
        rootItemSizesCache = sizes
        return sizes
    }

    /// Tamanhos dos textos livres do mural, memoizados enquanto o `board` não muda.
    public var freeTextSizes: [UUID: BoardSize] {
        let currentBoard = board
        if let freeTextSizesCache { return freeTextSizesCache }
        let sizes = Dictionary(
            uniqueKeysWithValues: currentBoard.freeTexts.map { freeText in
                let size = BoardLayout.size(of: freeText)
                return (freeText.id, BoardSize(width: size.width, height: size.height))
            })
        freeTextSizesCache = sizes
        return sizes
    }

    /// Extensão ocupada pelo mural solto, memoizada enquanto o `board` não muda.
    /// O getter ainda lê `board` antes do cache para manter a dependência observável.
    public var rootExtent: BoardSize {
        let _ = board
        if let rootExtentCache { return rootExtentCache }
        // Reutiliza os snapshots derivados que o canvas normalmente já pediu na mesma avaliação,
        // sem perder a leitura observável de `board` acima.
        let extent = BoardLayout.extent(of: rootItems, freeTexts: freeTexts)
        let result = BoardSize(width: extent.width, height: extent.height)
        rootExtentCache = result
        return result
    }

    public func children(of folderID: UUID) -> [BoardItem] {
        let currentBoard = board
        if let cached = childrenCache[folderID] { return cached }
        let children = currentBoard.children(of: folderID)
        if childrenCache.count >= Self.derivedCacheEntryLimit, let evicted = childrenCacheOrder.first {
            childrenCache.removeValue(forKey: evicted)
            childrenCacheOrder.removeFirst()
        }
        childrenCache[folderID] = children
        childrenCacheOrder.append(folderID)
        return children
    }
    /// Lookup by UUID uses a lazy index for the current board revision. The first
    /// occurrence wins, matching `Board.item(id:)` even if corrupted data repeats an ID.
    public func item(id: UUID) -> BoardItem? {
        let currentBoard = board
        if itemIndexCache == nil {
            var index: [UUID: Int] = [:]
            index.reserveCapacity(currentBoard.items.count)
            for (offset, item) in currentBoard.items.enumerated() {
                if index[item.id] == nil { index[item.id] = offset }
            }
            itemIndexCache = index
        }
        guard let offset = itemIndexCache?[id], currentBoard.items.indices.contains(offset) else { return nil }
        return currentBoard.items[offset]
    }
    /// Destinos memoizados enquanto o board não muda. Menus e gestos podem pedir os destinos de vários cartões
    /// durante a mesma avaliação; o cálculo puro de `Board` continua disponível para snapshots independentes.
    public func folderDestinations(for id: UUID) -> [FolderDestination] {
        let currentBoard = board
        if let cached = folderDestinationsCache[id] { return cached }
        guard let moving = item(id: id) else { return [] }
        if moving.kind != .folder, let cached = nonFolderFolderDestinationsCache[moving.parentID] {
            return cached
        }
        let destinations = currentBoard.folderDestinations(
            for: id,
            byParent: folderChildrenByParent(for: currentBoard),
            rootItems: rootItems)
        if moving.kind != .folder {
            let parentID = moving.parentID
            if nonFolderFolderDestinationsCache.count >= Self.derivedCacheEntryLimit,
                let evicted = nonFolderFolderDestinationsCacheOrder.first
            {
                nonFolderFolderDestinationsCache.removeValue(forKey: evicted)
                nonFolderFolderDestinationsCacheOrder.removeFirst()
            }
            nonFolderFolderDestinationsCache[parentID] = destinations
            nonFolderFolderDestinationsCacheOrder.append(parentID)
            return destinations
        }
        if folderDestinationsCache.count >= Self.derivedCacheEntryLimit, let evicted = folderDestinationsCacheOrder.first {
            folderDestinationsCache.removeValue(forKey: evicted)
            folderDestinationsCacheOrder.removeFirst()
        }
        folderDestinationsCache[id] = destinations
        folderDestinationsCacheOrder.append(id)
        return destinations
    }

    /// Índice da hierarquia compartilhado pelos menus de todos os cartões da mesma revisão do board.
    /// A ordenação é a mesma de `Board.children(of:)`; o cache é descartado em qualquer mutação.
    private func folderChildrenByParent(for currentBoard: Board) -> [UUID: [BoardItem]] {
        if let folderChildrenByParentCache { return folderChildrenByParentCache }
        var grouped: [UUID: [BoardItem]] = [:]
        for item in currentBoard.items {
            if let parentID = item.parentID {
                grouped[parentID, default: []].append(item)
            }
        }
        for parentID in grouped.keys {
            grouped[parentID]?.sort { $0.createdAt < $1.createdAt }
        }
        folderChildrenByParentCache = grouped
        return grouped
    }
    /// Lookup de texto livre por UUID usando um índice lazy da revisão atual do board.
    /// A primeira ocorrência vence, como em `Board.freeText(id:)` mesmo em dados corrompidos.
    public func freeText(id: UUID) -> BoardFreeText? {
        let currentBoard = board
        if freeTextIndexCache == nil {
            var index: [UUID: Int] = [:]
            index.reserveCapacity(currentBoard.freeTexts.count)
            for (offset, freeText) in currentBoard.freeTexts.enumerated() {
                if index[freeText.id] == nil { index[freeText.id] = offset }
            }
            freeTextIndexCache = index
        }
        guard let offset = freeTextIndexCache?[id], currentBoard.freeTexts.indices.contains(offset) else { return nil }
        return currentBoard.freeTexts[offset]
    }
    public func fileURL(for item: BoardItem) -> URL? { importer.fileURL(for: item) }

    /// URL de uma imagem citada numa nota, em `Items/`; `nil` se o nome não for de anexo seguro.
    public func noteImageURL(named name: String) -> URL? {
        guard NoteImageMarkup.isAttachmentName(name) else { return nil }
        return importer.itemsDirectory.appendingPathComponent(name)
    }

    // MARK: Entrada de conteúdo

    /// Copia arquivos para a pasta de itens e cria um cartão para cada um.
    /// Arquivos que falham são pulados e relatados em `lastError`.
    @discardableResult
    public func importFiles(_ urls: [URL], into parentID: UUID? = nil, at anchor: BoardPoint? = nil) -> [BoardItem] {
        var imported: [BoardItem] = []
        var failures: [String] = []
        for url in urls {
            do {
                let item = try importer.importFile(at: url, parentID: parentID)
                imported.append(item)
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        let created = insertBatch(imported, anchor: anchor)
        if !failures.isEmpty {
            lastError = "Não foi possível importar: \(failures.joined(separator: ", "))."
        }
        if !created.isEmpty { persist() }
        return created
    }

    @discardableResult
    public func importText(_ text: String, into parentID: UUID? = nil, at anchor: BoardPoint? = nil) -> BoardItem? {
        guard let item = try? importer.importText(text, parentID: parentID) else { return nil }
        let placed = insert(item, anchor: anchor)
        persist()
        return placed
    }

    /// Imagem ou outro conteúdo que chegou como dados (sem arquivo de origem).
    @discardableResult
    public func importData(_ data: Data, fileExtension: String, kind: ItemKind, title: String, into parentID: UUID? = nil) -> BoardItem? {
        do {
            let item = try importer.importData(data, fileExtension: fileExtension, kind: kind, title: title, parentID: parentID)
            let placed = insert(item)
            persist()
            return placed
        } catch {
            lastError = "Não foi possível guardar o conteúdo colado."
            return nil
        }
    }

    // MARK: Entrada de conteúdo fora do Main Actor

    /// Cartões já copiados para `Items/`, ainda fora do board, e os nomes que falharam.
    public struct PreparedImport: Sendable {
        public let items: [BoardItem]
        public let failures: [String]
    }

    /// A file whose content type was supplied by the provider rather than
    /// inferred from a temporary filename.
    public struct TypedFile: Sendable, Equatable {
        public let url: URL
        public let contentTypeIdentifier: String
        public let title: String?

        public init(url: URL, contentTypeIdentifier: String, title: String? = nil) {
            self.url = url
            self.contentTypeIdentifier = contentTypeIdentifier
            self.title = title
        }
    }

    /// Copia os arquivos e inspeciona as imagens fora do Main Actor: um vídeo grande
    /// não congela a janela. Nada entra no board até `commit(_:into:)`.
    public func prepareFiles(_ urls: [URL], parentID: UUID? = nil) async -> PreparedImport {
        await Self.copyFiles(urls, parentID: parentID, importer: importer)
    }

    /// Copies files whose uniform type is already known, preserving the
    /// provider's classification through staging and commit.
    public func prepareTypedFiles(_ files: [TypedFile], parentID: UUID? = nil) async -> PreparedImport {
        guard !Task.isCancelled else { return PreparedImport(items: [], failures: []) }
        return await Self.copyTypedFiles(files, parentID: parentID, importer: importer)
    }

    /// Grava dados colados (imagem, PDF) fora do Main Actor.
    public func prepareData(
        _ data: Data, fileExtension: String, kind: ItemKind, title: String, parentID: UUID? = nil
    ) async -> PreparedImport {
        await Self.writeData(
            data, fileExtension: fileExtension, kind: kind, title: title, parentID: parentID, importer: importer)
    }

    /// Grava uma imagem colada numa nota (dados em memória) fora do Main Actor.
    /// O arquivo fica em `Items/` sem ser citado: `addNoteAttachment` o liga à nota e `discardNoteImage` o apaga.
    public func prepareNoteImage(data: Data, fileExtension: String) async -> NoteAttachment? {
        await Self.writeNoteImage(data: data, fileExtension: fileExtension, importer: importer)
    }

    /// Copia uma imagem do disco para `Items/` fora do Main Actor, para colar numa nota.
    public func prepareNoteImage(fileAt url: URL) async -> NoteAttachment? {
        await Self.copyNoteImage(fileAt: url, importer: importer)
    }

    /// Insere no board os cartões preparados. A pasta de destino é conferida de novo:
    /// se ela sumiu durante a cópia, o conteúdo vai para o mural em vez de ficar órfão.
    @discardableResult
    public func commit(_ prepared: PreparedImport, into parentID: UUID? = nil, at anchor: BoardPoint? = nil) -> [BoardItem] {
        let folderExists = parentID.map { item(id: $0)?.kind == .folder } ?? true
        var items = prepared.items
        if !folderExists {
            for index in items.indices {
                items[index].parentID = nil
            }
        }
        let created = insertBatch(items, anchor: anchor)
        if !prepared.failures.isEmpty {
            lastError = "Não foi possível importar: \(prepared.failures.joined(separator: ", "))."
        }
        if !created.isEmpty { persist() }
        return created
    }

    /// Apaga os arquivos de uma importação que não vai mais entrar no board (a janela
    /// fechou ou mudou durante a cópia), para não deixar órfãos em `Items/`.
    public func discard(_ prepared: PreparedImport) {
        for item in prepared.items {
            importer.removeFile(of: item)
        }
    }

    @concurrent
    private nonisolated static func writeNoteImage(
        data: Data, fileExtension: String, importer: ItemImporter
    ) async -> NoteAttachment? {
        let signpost = MuralSignposts.importing.beginInterval("Gravar imagem da nota")
        defer { MuralSignposts.importing.endInterval("Gravar imagem da nota", signpost) }
        return try? importer.importNoteImage(data: data, fileExtension: fileExtension)
    }

    @concurrent
    private nonisolated static func copyNoteImage(fileAt url: URL, importer: ItemImporter) async -> NoteAttachment? {
        let signpost = MuralSignposts.importing.beginInterval("Copiar imagem da nota")
        defer { MuralSignposts.importing.endInterval("Copiar imagem da nota", signpost) }
        return try? importer.importNoteImage(fileAt: url)
    }

    @concurrent
    private nonisolated static func copyFiles(
        _ urls: [URL], parentID: UUID?, importer: ItemImporter
    ) async -> PreparedImport {
        let signpost = MuralSignposts.importing.beginInterval("Copiar arquivos")
        defer { MuralSignposts.importing.endInterval("Copiar arquivos", signpost) }
        var items: [BoardItem] = []
        var failures: [String] = []
        for url in urls {
            do {
                items.append(try importer.importFile(at: url, parentID: parentID))
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        return PreparedImport(items: items, failures: failures)
    }

    @concurrent
    private nonisolated static func copyTypedFiles(
        _ files: [TypedFile], parentID: UUID?, importer: ItemImporter
    ) async -> PreparedImport {
        let signpost = MuralSignposts.importing.beginInterval("Copiar arquivos tipados")
        defer { MuralSignposts.importing.endInterval("Copiar arquivos tipados", signpost) }
        var items: [BoardItem] = []
        var failures: [String] = []
        for file in files {
            guard !Task.isCancelled else { break }
            do {
                try Task.checkCancellation()
                items.append(
                    try importer.importFile(
                        at: file.url,
                        contentTypeIdentifier: file.contentTypeIdentifier,
                        title: file.title,
                        parentID: parentID))
                try Task.checkCancellation()
            } catch is CancellationError {
                break
            } catch {
                failures.append(file.title ?? file.url.lastPathComponent)
            }
        }
        return PreparedImport(items: items, failures: failures)
    }

    @concurrent
    private nonisolated static func writeData(
        _ data: Data, fileExtension: String, kind: ItemKind, title: String, parentID: UUID?, importer: ItemImporter
    ) async -> PreparedImport {
        let signpost = MuralSignposts.importing.beginInterval("Gravar conteúdo colado")
        defer { MuralSignposts.importing.endInterval("Gravar conteúdo colado", signpost) }
        do {
            let item = try importer.importData(
                data, fileExtension: fileExtension, kind: kind, title: title, parentID: parentID)
            return PreparedImport(items: [item], failures: [])
        } catch {
            return PreparedImport(items: [], failures: [title])
        }
    }

    /// Texto colado no tipo que o usuário escolheu no popup.
    @discardableResult
    public func importText(
        _ text: String, as kind: ItemKind, into parentID: UUID? = nil, at anchor: BoardPoint? = nil
    ) -> BoardItem? {
        guard let item = try? importer.importText(text, as: kind, parentID: parentID) else { return nil }
        let placed = insert(item, anchor: anchor)
        persist()
        return placed
    }

    // MARK: Cartões de texto

    /// Nota vazia, para ser escrita na página de leitura.
    @discardableResult
    public func createNote(into parentID: UUID? = nil) -> BoardItem {
        let placed = insert(BoardItem(kind: .text, title: "", parentID: parentID))
        persist()
        return placed
    }

    /// Post-it vazio, para ser escrito na versão ampliada.
    @discardableResult
    public func createSticky(
        into parentID: UUID? = nil, color: StickyColor = .yellow, at position: BoardPoint? = nil
    ) -> BoardItem {
        let placed = insert(BoardItem(kind: .sticky, title: "", parentID: parentID, stickyColor: color))
        if parentID != nil, let position {
            _ = board.placeInFolder(id: placed.id, at: position)
        }
        persist()
        return item(id: placed.id) ?? placed
    }

    // MARK: Lembretes

    /// Todos os cartões de lembrete do mural, de qualquer nível.
    public var reminderItems: [BoardItem] {
        let currentBoard = board
        if let reminderItemsCache { return reminderItemsCache }
        let reminders = currentBoard.items.filter { $0.kind == .reminder }
        reminderItemsCache = reminders
        return reminders
    }

    /// Cria um cartão para cada lembrete e grava uma vez ao final. O título do cartão é o do lembrete.
    @discardableResult
    public func addReminders(_ snapshots: [ReminderSnapshot], into parentID: UUID? = nil) -> [BoardItem] {
        let now = Date.now
        var pending: [BoardItem] = []
        for (index, snapshot) in snapshots.enumerated() {
            pending.append(
                BoardItem(
                    kind: .reminder,
                    title: snapshot.title,
                    createdAt: now.addingTimeInterval(Double(index) * 0.001),
                    parentID: parentID,
                    reminder: snapshot))
        }
        let created = insertBatch(pending)
        if !created.isEmpty { persist() }
        return created
    }

    /// Troca o estado guardado do lembrete; o título do cartão acompanha.
    /// - Returns: `false`, sem gravar, se o cartão não é um lembrete ou nada mudou.
    @discardableResult
    public func updateReminder(_ itemID: UUID, with snapshot: ReminderSnapshot) -> Bool {
        guard var item = item(id: itemID), item.kind == .reminder,
            item.reminder != snapshot || (item.reminder?.title != snapshot.title && item.title == item.reminder?.title)
        else { return false }
        let previousTitle = item.reminder?.title
        item.reminder = snapshot
        if item.title == previousTitle { item.title = snapshot.title }
        board.update(item)
        persist()
        return true
    }

    /// Marca o lembrete como apagado no Lembretes, mantendo o último estado conhecido.
    public func markReminderMissing(_ itemID: UUID) {
        guard var item = item(id: itemID), item.kind == .reminder, var snapshot = item.reminder,
            !snapshot.isMissing
        else { return }
        snapshot.isMissing = true
        item.reminder = snapshot
        board.update(item)
        persist()
    }

    // MARK: Pastas

    /// Pasta vazia, solta no mural numa posição livre. Sem nome, vira "Nova pasta".
    @discardableResult
    public func createFolder(named name: String) -> BoardItem {
        let placed = insert(BoardItem(kind: .folder, title: Self.folderTitle(from: name)))
        persist()
        return placed
    }

    /// Pasta vazia dentro de outra pasta. Sem nome, vira "Nova pasta".
    /// - Returns: `nil`, sem criar nada, se o pai não é uma pasta ou já está no último nível (`Board.maximumFolderDepth`).
    @discardableResult
    public func createFolder(named name: String, into parentID: UUID) -> BoardItem? {
        guard canCreateFolder(in: parentID) else { return nil }
        let placed = insert(BoardItem(kind: .folder, title: Self.folderTitle(from: name), parentID: parentID))
        persist()
        return placed
    }

    /// Renomeia uma pasta, sem espaços nas pontas.
    /// - Returns: `false`, sem mudar nada, se o item não é pasta, o nome fica vazio ou é igual ao atual.
    @discardableResult
    public func renameFolder(_ itemID: UUID, to name: String) -> Bool {
        guard var item = item(id: itemID), item.kind == .folder else { return false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != item.title else { return false }
        item.title = clean
        board.update(item)
        persist()
        return true
    }

    /// Renomeia qualquer cartão sem alterar seu conteúdo ou a legenda.
    /// - Returns: `false` se o cartão não existe, o nome fica vazio ou não mudou.
    @discardableResult
    public func renameItem(_ itemID: UUID, to name: String) -> Bool {
        guard var item = item(id: itemID) else { return false }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != item.title else { return false }
        item.title = clean
        board.update(item)
        persist()
        return true
    }

    /// Diz se cabe uma pasta nova no pai: `nil` é o mural, que sempre aceita; uma pasta aceita enquanto a nova
    /// não passar do último nível (`Board.maximumFolderDepth`).
    public func canCreateFolder(in parentID: UUID?) -> Bool {
        guard let parentID else { return true }
        guard item(id: parentID)?.kind == .folder else { return false }
        // A pasta nova ficaria um nível abaixo do pai, que já está um nível abaixo das pastas que o cercam.
        return board.depth(of: parentID) + 2 <= Board.maximumFolderDepth
    }

    /// Grava título e corpo (Markdown) de uma nota. Sem título, usa a primeira linha do corpo.
    /// Corpo novo descarta as frases curtas escolhidas para o anterior.
    public func updateNote(_ itemID: UUID, title: String, text: String) {
        guard var item = item(id: itemID), item.kind == .text else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty ? (body.map { ContentClassifier.title(forText: $0) } ?? "") : cleanTitle
        guard item.title != resolvedTitle || item.text != body else { return }
        if item.text != body { item.keySentences = nil }
        item.title = resolvedTitle
        item.text = body
        let dropped = reconcileAttachments(of: &item)
        board.update(item)
        releaseFiles(named: dropped, saved: persist())
    }

    /// Marca ou desmarca a tarefa do bloco `segment` da nota. `source` é o texto que a página mostrava:
    /// se a nota mudou desde então, nada muda. As frases curtas guardadas continuam valendo, porque só a caixa muda.
    /// - Returns: `false`, sem alterar nada, se o cartão não é uma nota, o texto não é mais `source` ou o bloco não é tarefa.
    @discardableResult
    public func toggleNoteTask(_ itemID: UUID, segment: Int, in source: String) -> Bool {
        guard var item = item(id: itemID), item.kind == .text, item.text == source,
            let toggled = TextSegmenter.segment(source).togglingTask(inSegment: segment)
        else { return false }
        if let record = item.keySentences, record.matches(source) {
            item.keySentences = record.rehashed(for: toggled)
        }
        item.text = toggled
        board.update(item)
        persist()
        return true
    }

    /// Liga uma imagem já gravada à nota e grava o mural: o arquivo fica citado na hora, então
    /// uma queda antes de a nota ser concluída não deixa arquivo órfão.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe ou não é uma nota.
    @discardableResult
    public func addNoteAttachment(_ attachment: NoteAttachment, to itemID: UUID) -> Bool {
        guard var item = item(id: itemID), item.kind == .text else { return false }
        var attachments = item.attachments ?? []
        guard !attachments.contains(where: { $0.fileName == attachment.fileName }) else { return true }
        attachments.append(attachment)
        item.attachments = attachments
        board.update(item)
        persist()
        return true
    }

    /// Apaga o arquivo de uma imagem preparada que não entrou na nota, se nenhum cartão o cita.
    public func discardNoteImage(_ attachment: NoteAttachment) {
        guard !isPersistenceSuspended, !citedFileNames(in: board).contains(attachment.fileName) else { return }
        importer.removeFile(named: attachment.fileName)
    }

    /// Grava texto e cor de um post-it. O título acompanha a primeira linha.
    public func updateSticky(_ itemID: UUID, text: String, color: StickyColor) {
        guard var item = item(id: itemID), item.kind == .sticky else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty ? nil : trimmed
        guard item.text != body || item.stickyColor != color else { return }
        item.text = body
        item.title = body.map { ContentClassifier.title(forText: $0) } ?? ""
        item.stickyColor = color
        board.update(item)
        persist()
    }

    /// Define a cor do cartão (`nil` tira a cor). Vale para qualquer tipo de cartão.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe ou já tem essa cor.
    @discardableResult
    public func setColorTag(_ color: TagColor?, for itemID: UUID) -> Bool {
        guard var item = item(id: itemID), item.colorTag != color else { return false }
        item.colorTag = color
        board.update(item)
        persist()
        return true
    }

    /// Guarda as frases curtas escolhidas, se ainda valem para o texto atual do cartão
    /// (ele pode ter mudado enquanto o modelo escolhia).
    @discardableResult
    public func setKeySentences(_ record: KeySentenceRecord, for itemID: UUID) -> Bool {
        guard var item = item(id: itemID), let source = NoteFolding.source(of: item), record.matches(source) else {
            return false
        }
        guard item.keySentences != record else { return true }
        item.keySentences = record
        board.update(item)
        persist()
        return true
    }

    // MARK: Alterações

    /// Cria um texto livre diretamente no mural, em uma posição livre da grade.
    @discardableResult
    public func createFreeText(_ text: String = "", at position: BoardPoint? = nil) -> BoardFreeText {
        let position = BoardLayout.clamped(
            position ?? BoardLayout.freeTextPosition(avoiding: board.rootItems, freeTexts: board.freeTexts)
        )
        let freeText = BoardFreeText(text: text, position: position)
        board.add(freeText)
        persist()
        return freeText
    }

    /// Atualiza o conteúdo de um texto livre, aplicando o limite de caracteres do domínio.
    /// - Returns: `false` quando o texto não existe ou já tinha o mesmo conteúdo normalizado.
    @discardableResult
    public func updateFreeText(_ freeTextID: UUID, text: String) -> Bool {
        guard var freeText = freeText(id: freeTextID) else { return false }
        let normalized = BoardFreeText.normalized(text)
        guard freeText.text != normalized else { return false }
        freeText.text = normalized
        board.update(freeText)
        persist()
        return true
    }

    /// Move um texto livre e mantém o ponto dentro do mural.
    @discardableResult
    public func moveFreeText(_ freeTextID: UUID, to position: BoardPoint) -> Bool {
        guard let current = freeText(id: freeTextID), current.position != BoardLayout.clamped(position) else {
            return false
        }
        board.moveFreeText(id: freeTextID, to: position)
        persist()
        return true
    }

    /// Muda o tamanho de um texto livre (regras em `Board.resizeFreeText`): `nil`, ou o tamanho padrão, devolve o quadrado padrão.
    /// - Returns: `false` quando o texto não existe ou já tinha esse tamanho.
    @discardableResult
    public func resizeFreeText(_ freeTextID: UUID, to size: BoardSize?) -> Bool {
        guard board.resizeFreeText(id: freeTextID, to: size) else { return false }
        persist()
        return true
    }

    /// Apaga um texto livre sem tocar nos arquivos dos cartões.
    @discardableResult
    public func deleteFreeText(_ freeTextID: UUID) -> Bool {
        guard !isPersistenceSuspended else {
            lastError = "Não foi possível apagar o texto livre: a persistência está suspensa."
            return false
        }
        var candidate = board
        guard candidate.removeFreeText(id: freeTextID) else { return false }
        guard persistence == .deferred else {
            do {
                try store.save(candidate)
            } catch {
                lastError = "Não foi possível apagar o texto livre: \(error.localizedDescription)."
                return false
            }
            board = candidate
            return true
        }
        board = candidate
        return true
    }

    public func toggleChecklistEntry(_ entryID: UUID, in itemID: UUID) {
        guard var item = item(id: itemID), item.checklist != nil else { return }
        item.checklist?.toggle(entryID: entryID)
        board.update(item)
        persist()
    }

    public func setCaption(_ text: String, for itemID: UUID) {
        guard var item = item(id: itemID) else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = clean.isEmpty ? nil : clean
        guard item.caption != caption else { return }
        item.caption = caption
        board.update(item)
        persist()
    }

    /// Muda a posição de um cartão solto (arredondada e nunca abaixo de 0) e o leva para cima dos outros.
    public func move(_ itemID: UUID, to position: BoardPoint) {
        guard board.move(id: itemID, to: BoardLayout.clamped(position)) else { return }
        persist()
    }

    /// Muda o tamanho de um cartão solto (regras em `Board.resize`, hoje só post-it): `nil`, ou o tamanho padrão do tipo, devolve
    /// o cartão ao padrão. Não muda a posição nem leva o cartão para cima dos outros.
    /// - Returns: `false` quando o cartão não existe, não muda de tamanho ou já tinha esse tamanho.
    @discardableResult
    public func resize(_ itemID: UUID, to size: BoardSize?) -> Bool {
        guard board.resize(id: itemID, to: size) else { return false }
        persist()
        return true
    }

    /// Põe o post-it num lugar livre da pasta onde ele está, por cima dos outros (regras em `Board.placeInFolder`).
    public func placeInFolder(_ itemID: UUID, at position: BoardPoint) {
        guard board.placeInFolder(id: itemID, at: position) else { return }
        persist()
    }

    /// Muda a posição de vários cartões soltos de uma vez (organizar), sem mexer em quem fica por cima.
    /// - Returns: onde estavam os cartões que mudaram de lugar, para desfazer.
    @discardableResult
    public func arrange(_ positions: [UUID: BoardPoint]) -> [UUID: BoardPoint] {
        let previous = Dictionary(
            uniqueKeysWithValues: board.rootItems.compactMap { item -> (UUID, BoardPoint)? in
                guard let position = positions[item.id], position != item.position else { return nil }
                return (item.id, item.position)
            })
        guard board.setPositions(positions) > 0 else { return [:] }
        persist()
        return previous
    }

    /// Guarda um cartão, ou uma pasta com tudo que há nela, dentro de outra pasta (regras em `Board.moveIntoFolder`).
    public func moveIntoFolder(_ itemID: UUID, folderID: UUID) {
        guard board.moveIntoFolder(id: itemID, folderID: folderID) else { return }
        persist()
    }

    /// Tira o cartão de dentro da pasta e o solta no mural, numa posição livre (a mesma regra de colar).
    public func moveToBoard(_ itemID: UUID) {
        guard let item = item(id: itemID), item.parentID != nil else { return }
        // A vaga é do tamanho que o cartão tem: um post-it redimensionado guarda o tamanho dentro da pasta.
        let position = BoardLayout.freePosition(for: item, avoiding: board.rootItems)
        guard board.moveToBoard(id: itemID, at: position) else { return }
        persist()
    }

    /// Sobe o cartão um nível: da pasta para a pasta que a guarda ou, se a pasta está solta, para o mural.
    /// Um cartão que já está solto fica como está.
    public func moveUp(_ itemID: UUID) {
        guard let parentID = item(id: itemID)?.parentID else { return }
        if let grandparentID = item(id: parentID)?.parentID {
            moveIntoFolder(itemID, folderID: grandparentID)
        } else {
            moveToBoard(itemID)
        }
    }

    /// Quantos cartões há dentro da pasta, em qualquer nível. As subpastas contam como cartões.
    public func descendantCount(of folderID: UUID) -> Int {
        let currentBoard = board
        guard item(id: folderID)?.kind == .folder else { return 0 }
        return currentBoard.descendantCount(
            of: folderID,
            byParent: folderChildrenByParent(for: currentBoard))
    }

    /// Apaga o cartão (e, se for pasta, tudo que há dentro dela, em qualquer nível) junto com os arquivos guardados.
    public func delete(_ itemID: UUID) {
        guard !isPersistenceSuspended else {
            lastError = "Não foi possível apagar o item: a persistência está suspensa. Nenhum arquivo foi removido."
            return
        }

        var candidate = board
        let removed = candidate.remove(id: itemID)
        guard !removed.isEmpty else { return }
        let names = removed.flatMap(\.assetFileNames)
        if persistence == .deferred {
            board = candidate
            deferredDeletions.formUnion(names)
            return
        }
        do {
            // O mural precisa estar gravado antes de publicar a remoção em memória
            // ou apagar os arquivos que ele ainda referencia.
            try store.save(candidate)
        } catch {
            lastError = "Não foi possível apagar o item: \(error.localizedDescription). Nenhum arquivo foi removido."
            return
        }

        board = candidate
        let cited = citedFileNames(in: candidate)
        for name in names where !cited.contains(name) {
            importer.removeFile(named: name)
        }
    }

    /// Finaliza a remoção de arquivos somente depois de a sessão ter publicado
    /// com sucesso o snapshot transacional do novo board.
    public func finalizeDeferredDeletions() {
        finalizeDeferredDeletions(persistedBoard: board)
    }

    /// Apaga só os arquivos que a versão gravada (`persistedBoard`) já não cita em nenhum cartão.
    /// Uma exclusão feita enquanto a gravação acontecia continua adiada até a próxima,
    /// para que o disco nunca tenha um board apontando para um arquivo já apagado.
    /// Um nome que o mural atual voltou a citar sai da fila sem ser apagado.
    public func finalizeDeferredDeletions(persistedBoard: Board) {
        guard persistence == .deferred, !deferredDeletions.isEmpty else { return }
        let persisted = citedFileNames(in: persistedBoard)
        let current = citedFileNames(in: board)
        var pending = Set<String>()
        for name in deferredDeletions {
            if current.contains(name) { continue }
            if persisted.contains(name) {
                pending.insert(name)
            } else {
                importer.removeFile(named: name)
            }
        }
        deferredDeletions = pending
    }

    // MARK: Interno

    private static func folderTitle(from name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nova pasta" : trimmed
    }

    /// Cartões soltos no mural ganham uma posição livre; os de pasta não precisam.
    func insert(_ item: BoardItem, anchor: BoardPoint? = nil) -> BoardItem {
        insertBatch([item], anchor: anchor)[0]
    }

    /// Insere um lote calculando as vagas livres uma única vez contra o snapshot atual dos cartões raiz.
    /// Itens que já pertencem a uma pasta não participam do posicionamento do mural.
    func insertBatch(_ items: [BoardItem], anchor: BoardPoint? = nil) -> [BoardItem] {
        guard !items.isEmpty else { return [] }
        var placed = items
        let rootIndices = placed.indices.filter { placed[$0].parentID == nil }
        if !rootIndices.isEmpty {
            let positions = BoardLayout.importPositions(
                kinds: rootIndices.map { placed[$0].kind }, anchor: anchor, avoiding: board.rootItems)
            for (index, position) in zip(rootIndices, positions) {
                placed[index].position = position
            }
        }
        var updatedBoard = board
        updatedBoard.items.append(contentsOf: placed)
        updatedBoard.formatVersion = updatedBoard.requiredFormatVersion
        board = updatedBoard
        return placed
    }

    @discardableResult
    func persist() -> Bool {
        guard persistence == .immediate, !isPersistenceSuspended else { return false }
        do {
            try store.save(board)
            return true
        } catch {
            lastError = "Não foi possível salvar o mural: \(error.localizedDescription)"
            return false
        }
    }

    /// Nomes de arquivo citados por algum cartão do mural.
    private func citedFileNames(in board: Board) -> Set<String> {
        Set(board.items.flatMap(\.assetFileNames))
    }

    /// Ajusta os anexos da nota ao texto: fica quem o texto cita, e um nome citado cujo arquivo existe entra
    /// com o tamanho lido do arquivo.
    /// - Returns: os nomes que deixaram de ser anexos da nota.
    private func reconcileAttachments(of item: inout BoardItem) -> [String] {
        let referenced = NoteImageMarkup.referencedFileNames(in: item.text ?? "")
        let old = item.attachments ?? []
        var kept = old.filter { referenced.contains($0.fileName) }
        for name in referenced where !kept.contains(where: { $0.fileName == name }) {
            let url = importer.itemsDirectory.appendingPathComponent(name)
            guard let metadata = ImageInspector.inspect(url) else { continue }
            kept.append(NoteAttachment(fileName: name, pixelWidth: metadata.pixelWidth, pixelHeight: metadata.pixelHeight))
        }
        item.attachments = kept.isEmpty ? nil : kept
        return old.map(\.fileName).filter { name in !kept.contains { $0.fileName == name } }
    }

    /// Manda para a remoção os arquivos que saíram de uma nota: no modo imediato, apaga os que o mural
    /// gravado já não cita; no adiado, espera a gravação da sessão.
    private func releaseFiles(named names: [String], saved: Bool) {
        guard !names.isEmpty else { return }
        if persistence == .deferred {
            deferredDeletions.formUnion(names)
        } else if saved {
            let cited = citedFileNames(in: board)
            for name in names where !cited.contains(name) { importer.removeFile(named: name) }
        }
    }
}
