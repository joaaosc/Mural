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
    /// Verdadeiro quando o mural salvo não pôde ser lido nem guardado à parte: nada é
    /// gravado, para não sobrescrever o arquivo original com um mural novo.
    public private(set) var isPersistenceSuspended = false

    @ObservationIgnored let store: BoardStore
    @ObservationIgnored let importer: ItemImporter

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
        guard !isPersistenceSuspended else { return }
        do {
            try store.save(board)
        } catch {
            lastError = "Não foi possível salvar o mural: \(error.localizedDescription)"
        }
    }
}
