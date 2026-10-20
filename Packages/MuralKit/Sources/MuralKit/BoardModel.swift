import Foundation
import Observation

/// Estado vivo do mural: carrega do disco, aplica mudanças e grava após cada uma.
///
/// Fica no pacote de domínio para ser testado sem interface; a interface só
/// observa `board` e chama os métodos de alteração.
@MainActor
@Observable
public final class BoardModel {
    public private(set) var board: Board
    /// Última falha a mostrar ao usuário (importação, gravação, arquivo corrompido).
    public var lastError: String?

    @ObservationIgnored public let store: BoardStore
    @ObservationIgnored public let importer: ItemImporter

    /// - Parameter seedIfEmpty: na primeira abertura, começa com o mural de exemplo.
    public init(store: BoardStore, seedIfEmpty: Bool = true) {
        self.store = store
        self.importer = ItemImporter(itemsDirectory: store.itemsDirectory)
        let empty = seedIfEmpty ? SampleBoard.make() : Board()
        do {
            if let loaded = try store.load() {
                board = loaded
            } else {
                board = empty
                persist()
            }
        } catch {
            board = empty
            let moved = try? store.quarantineCorruptedFile()
            lastError =
                "O mural salvo estava ilegível e foi guardado como \(moved?.lastPathComponent ?? "cópia"). Um mural novo foi criado."
            persist()
        }
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

    /// Apaga o cartão (e, se for pasta, o conteúdo dela) junto com os arquivos guardados.
    public func delete(_ itemID: UUID) {
        let doomed = board.items.filter { $0.id == itemID || $0.parentID == itemID }
        for item in doomed {
            importer.removeFile(of: item)
        }
        board.remove(id: itemID)
        persist()
    }

    public func move(_ itemID: UUID, to position: BoardPoint) {
        guard var item = board.item(id: itemID) else { return }
        item.position = position
        board.update(item)
        persist()
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
        do {
            try store.save(board)
        } catch {
            lastError = "Não foi possível salvar o mural: \(error.localizedDescription)"
        }
    }
}
