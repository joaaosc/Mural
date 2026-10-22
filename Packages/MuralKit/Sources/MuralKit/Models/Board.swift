import Foundation

/// O mural inteiro: todos os cartões, soltos ou dentro de pastas.
public struct Board: Codable, Equatable, Sendable {
    /// Versão do formato gravado em disco, para migrações futuras.
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var items: [BoardItem]

    public init(items: [BoardItem] = []) {
        self.formatVersion = Self.currentFormatVersion
        self.items = items
    }

    /// Cartões soltos no mural (sem pasta).
    public var rootItems: [BoardItem] {
        items.filter { $0.parentID == nil }
    }

    /// Cartões dentro de uma pasta, na ordem de criação.
    public func children(of folderID: UUID) -> [BoardItem] {
        items.filter { $0.parentID == folderID }.sorted { $0.createdAt < $1.createdAt }
    }

    public func item(id: UUID) -> BoardItem? {
        items.first { $0.id == id }
    }

    public mutating func add(_ item: BoardItem) {
        items.append(item)
    }

    public mutating func update(_ item: BoardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    /// Remove o cartão e, se for pasta, tudo que estiver dentro dela.
    /// - Returns: os cartões removidos (para apagar os arquivos guardados).
    @discardableResult
    public mutating func remove(id: UUID) -> [BoardItem] {
        let removed = items.filter { $0.id == id || $0.parentID == id }
        items.removeAll { $0.id == id || $0.parentID == id }
        return removed
    }

    /// Muda a posição de um cartão solto e o leva para o fim da lista, que o mural desenha por cima dos outros.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe ou está dentro de uma pasta.
    @discardableResult
    public mutating func move(id: UUID, to position: BoardPoint) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].parentID == nil else { return false }
        var item = items.remove(at: index)
        item.position = position
        items.append(item)
        return true
    }

    /// Muda a posição de vários cartões soltos de uma vez (organizar), sem mexer na ordem da lista:
    /// quem estava por cima continua por cima. Ids desconhecidos e cartões de pasta são ignorados.
    /// - Returns: quantos cartões mudaram de lugar.
    @discardableResult
    public mutating func setPositions(_ positions: [UUID: BoardPoint]) -> Int {
        var changed = 0
        for index in items.indices where items[index].parentID == nil {
            guard let position = positions[items[index].id], items[index].position != position else { continue }
            items[index].position = position
            changed += 1
        }
        return changed
    }

    /// Guarda um cartão solto numa pasta solta. A posição do cartão e a ordem da lista não mudam.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe, já está numa pasta ou é uma pasta
    ///   (pasta não entra em pasta), ou se o destino não é uma pasta solta.
    @discardableResult
    public mutating func moveIntoFolder(id: UUID, folderID: UUID) -> Bool {
        guard id != folderID,
            let index = items.firstIndex(where: { $0.id == id }),
            items[index].parentID == nil, items[index].kind != .folder,
            let folder = item(id: folderID), folder.kind == .folder, folder.parentID == nil
        else { return false }
        items[index].parentID = folderID
        return true
    }

    /// Tira um cartão de dentro de uma pasta e o solta no mural, no fim da lista (por cima dos outros).
    /// - Returns: `false`, sem alterar nada, se o cartão não existe ou já está solto.
    @discardableResult
    public mutating func moveToBoard(id: UUID, at position: BoardPoint) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].parentID != nil else { return false }
        var item = items.remove(at: index)
        item.parentID = nil
        item.position = position
        items.append(item)
        return true
    }
}
