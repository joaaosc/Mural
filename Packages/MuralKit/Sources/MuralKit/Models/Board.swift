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
    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id || $0.parentID == id }
    }
}
