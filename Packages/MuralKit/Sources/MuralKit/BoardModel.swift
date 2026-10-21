import Foundation
import Observation

/// Estado vivo do mural: carrega do disco, aplica mudanças e grava após cada uma.
///
/// Fica no pacote de domínio para ser testado sem interface; a interface só
/// observa `board` e chama os métodos de alteração.
@MainActor
@Observable
public final class BoardModel {
    public enum Persistence: Sendable, Equatable {
        case immediate
        case deferred
    }

    public private(set) var board: Board
    /// Última falha a mostrar ao usuário (importação, gravação, arquivo corrompido).
    public var lastError: String?
    /// Verdadeiro quando o mural salvo não pôde ser lido nem guardado à parte: nada é
    /// gravado, para não sobrescrever o arquivo original com um mural novo.
    public private(set) var isPersistenceSuspended = false

    @ObservationIgnored let store: BoardStore
    @ObservationIgnored let importer: ItemImporter
    @ObservationIgnored let persistence: Persistence
    @ObservationIgnored private var deferredDeletions: [BoardItem] = []

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

    public var rootItems: [BoardItem] { board.rootItems }
    public func children(of folderID: UUID) -> [BoardItem] { board.children(of: folderID) }
    public func item(id: UUID) -> BoardItem? { board.item(id: id) }
    public func fileURL(for item: BoardItem) -> URL? { importer.fileURL(for: item) }

    // MARK: Entrada de conteúdo

    /// Copia arquivos para a pasta de itens e cria um cartão para cada um.
    /// Arquivos que falham são pulados e relatados em `lastError`.
    @discardableResult
    public func importFiles(_ urls: [URL], into parentID: UUID? = nil) -> [BoardItem] {
        var created: [BoardItem] = []
        var failures: [String] = []
        for url in urls {
            do {
                let item = try importer.importFile(at: url, parentID: parentID)
                created.append(insert(item))
            } catch {
                failures.append(url.lastPathComponent)
            }
        }
        if !failures.isEmpty {
            lastError = "Não foi possível importar: \(failures.joined(separator: ", "))."
        }
        if !created.isEmpty { persist() }
        return created
    }

    @discardableResult
    public func importText(_ text: String, into parentID: UUID? = nil) -> BoardItem? {
        guard let item = try? importer.importText(text, parentID: parentID) else { return nil }
        let placed = insert(item)
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

    /// Copia os arquivos e inspeciona as imagens fora do Main Actor: um vídeo grande
    /// não congela a janela. Nada entra no board até `commit(_:into:)`.
    public func prepareFiles(_ urls: [URL], parentID: UUID? = nil) async -> PreparedImport {
        await Self.copyFiles(urls, parentID: parentID, importer: importer)
    }

    /// Grava dados colados (imagem, PDF) fora do Main Actor.
    public func prepareData(
        _ data: Data, fileExtension: String, kind: ItemKind, title: String, parentID: UUID? = nil
    ) async -> PreparedImport {
        await Self.writeData(
            data, fileExtension: fileExtension, kind: kind, title: title, parentID: parentID, importer: importer)
    }

    /// Insere no board os cartões preparados. A pasta de destino é conferida de novo:
    /// se ela sumiu durante a cópia, o conteúdo vai para o mural em vez de ficar órfão.
    @discardableResult
    public func commit(_ prepared: PreparedImport, into parentID: UUID? = nil) -> [BoardItem] {
        let folderExists = parentID.map { board.item(id: $0)?.kind == .folder } ?? true
        var created: [BoardItem] = []
        for var item in prepared.items {
            if !folderExists { item.parentID = nil }
            created.append(insert(item))
        }
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
    public func importText(_ text: String, as kind: ItemKind, into parentID: UUID? = nil) -> BoardItem? {
        guard let item = try? importer.importText(text, as: kind, parentID: parentID) else { return nil }
        let placed = insert(item)
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
    public func createSticky(into parentID: UUID? = nil, color: StickyColor = .yellow) -> BoardItem {
        let placed = insert(BoardItem(kind: .sticky, title: "", parentID: parentID, stickyColor: color))
        persist()
        return placed
    }

    /// Grava título e corpo (Markdown) de uma nota. Sem título, usa a primeira linha do corpo.
    /// Corpo novo descarta as frases curtas escolhidas para o anterior.
    public func updateNote(_ itemID: UUID, title: String, text: String) {
        guard var item = board.item(id: itemID), item.kind == .text else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = cleanTitle.isEmpty ? (body.map { ContentClassifier.title(forText: $0) } ?? "") : cleanTitle
        guard item.title != resolvedTitle || item.text != body else { return }
        if item.text != body { item.keySentences = nil }
        item.title = resolvedTitle
        item.text = body
        board.update(item)
        persist()
    }

    /// Grava texto e cor de um post-it. O título acompanha a primeira linha.
    public func updateSticky(_ itemID: UUID, text: String, color: StickyColor) {
        guard var item = board.item(id: itemID), item.kind == .sticky else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.isEmpty ? nil : trimmed
        guard item.text != body || item.stickyColor != color else { return }
        item.text = body
        item.title = body.map { ContentClassifier.title(forText: $0) } ?? ""
        item.stickyColor = color
        board.update(item)
        persist()
    }

    /// Guarda as frases curtas escolhidas, se ainda valem para o texto atual do cartão
    /// (ele pode ter mudado enquanto o modelo escolhia).
    @discardableResult
    public func setKeySentences(_ record: KeySentenceRecord, for itemID: UUID) -> Bool {
        guard var item = board.item(id: itemID), let source = NoteFolding.source(of: item), record.matches(source) else {
            return false
        }
        guard item.keySentences != record else { return true }
        item.keySentences = record
        board.update(item)
        persist()
        return true
    }

    // MARK: Alterações

    public func toggleChecklistEntry(_ entryID: UUID, in itemID: UUID) {
        guard var item = board.item(id: itemID), item.checklist != nil else { return }
        item.checklist?.toggle(entryID: entryID)
        board.update(item)
        persist()
    }

    public func setCaption(_ text: String, for itemID: UUID) {
        guard var item = board.item(id: itemID) else { return }
        item.text = text.isEmpty ? nil : text
        board.update(item)
        persist()
    }

    /// Muda a posição de um cartão solto (arredondada e nunca abaixo de 0) e o leva para cima dos outros.
    public func move(_ itemID: UUID, to position: BoardPoint) {
        guard board.move(id: itemID, to: BoardLayout.clamped(position)) else { return }
        persist()
    }

    /// Guarda um cartão solto dentro de uma pasta.
    public func moveIntoFolder(_ itemID: UUID, folderID: UUID) {
        guard board.moveIntoFolder(id: itemID, folderID: folderID) else { return }
        persist()
    }

    /// Tira o cartão de dentro da pasta e o solta no mural, numa posição livre (a mesma regra de colar).
    public func moveToBoard(_ itemID: UUID) {
        guard let item = board.item(id: itemID), item.parentID != nil else { return }
        let position = BoardLayout.freePosition(for: item.kind, avoiding: board.rootItems)
        guard board.moveToBoard(id: itemID, at: position) else { return }
        persist()
    }

    /// Apaga o cartão (e, se for pasta, o conteúdo dela) junto com os arquivos guardados.
    public func delete(_ itemID: UUID) {
        guard !isPersistenceSuspended else {
            lastError = "Não foi possível apagar o item: a persistência está suspensa. Nenhum arquivo foi removido."
            return
        }

        var candidate = board
        let removed = candidate.remove(id: itemID)
        guard !removed.isEmpty else { return }
        if persistence == .deferred {
            board = candidate
            deferredDeletions.append(contentsOf: removed)
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
        for item in removed {
            importer.removeFile(of: item)
        }
    }

    /// Finaliza a remoção de arquivos somente depois de a sessão ter publicado
    /// com sucesso o snapshot transacional do novo board.
    public func finalizeDeferredDeletions() {
        guard persistence == .deferred else { return }
        let removed = deferredDeletions
        deferredDeletions.removeAll(keepingCapacity: true)
        for item in removed {
            importer.removeFile(of: item)
        }
    }

    /// Apaga só a mídia dos itens que a versão gravada (`persistedBoard`) já não contém.
    /// Uma exclusão feita enquanto a gravação acontecia continua adiada até a próxima,
    /// para que o disco nunca tenha um board apontando para um arquivo já apagado.
    public func finalizeDeferredDeletions(persistedBoard: Board) {
        guard persistence == .deferred else { return }
        var pending: [BoardItem] = []
        for item in deferredDeletions {
            if persistedBoard.item(id: item.id) == nil {
                importer.removeFile(of: item)
            } else {
                pending.append(item)
            }
        }
        deferredDeletions = pending
    }

    // MARK: Interno

    /// Cartões soltos no mural ganham uma posição livre; os de pasta não precisam.
    private func insert(_ item: BoardItem) -> BoardItem {
        var placed = item
        if placed.parentID == nil {
            placed.position = BoardLayout.freePosition(for: placed.kind, avoiding: board.rootItems)
        }
        board.add(placed)
        return placed
    }

    private func persist() {
        guard persistence == .immediate, !isPersistenceSuspended else { return }
        do {
            try store.save(board)
        } catch {
            lastError = "Não foi possível salvar o mural: \(error.localizedDescription)"
        }
    }
}
