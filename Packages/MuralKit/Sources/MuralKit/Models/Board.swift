import Foundation

/// O mural inteiro: todos os cartões, soltos ou dentro de pastas.
public struct Board: Codable, Equatable, Sendable {
    /// A versão mais nova do formato que esta build lê. Uma build recusa abrir um mural de versão maior
    /// que a sua (`BoardRepositoryError.futureBoardFormat`).
    /// - 2: pasta dentro de pasta (a versão 1 só tinha pastas soltas no mural).
    /// - 3: cartão de link.
    public static let currentFormatVersion = 3

    /// Quantos níveis de pasta podem ficar uns dentro dos outros. Uma pasta solta no mural é o nível 1;
    /// uma pasta nunca fica abaixo do nível 8. Cartões que não são pasta cabem em qualquer pasta.
    public static let maximumFolderDepth = 8

    /// Versão do formato que o conteúdo exigia quando o mural foi gravado. Toda alteração de fato grava
    /// `requiredFormatVersion`: um mural antigo só muda de versão junto com uma mudança real (e, portanto,
    /// com uma revisão nova), e um mural que não usa nada novo continua abrindo nas builds anteriores.
    public var formatVersion: Int
    public var items: [BoardItem]

    public init(items: [BoardItem] = []) {
        self.items = items
        self.formatVersion = Self.minimumFormatVersion(for: items)
    }

    /// A menor versão do formato que guarda este conteúdo sem perder nada: numa build anterior a ela, o mural
    /// não abriria ou perderia ao gravar o que ela não conhece. Cada versão nova do formato precisa de uma regra aqui.
    public var requiredFormatVersion: Int { Self.minimumFormatVersion(for: items) }

    static func minimumFormatVersion(for items: [BoardItem]) -> Int {
        var version = 1
        if items.contains(where: { $0.kind == .folder && $0.parentID != nil }) { version = max(version, 2) }
        if items.contains(where: { $0.kind == .link }) { version = max(version, 3) }
        return version
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

    // MARK: Hierarquia

    /// As pastas acima do cartão, da mais próxima à solta no mural. Para no primeiro pai ausente,
    /// que não é pasta ou já visto (guarda contra ciclo em dado corrompido).
    public func ancestors(of id: UUID) -> [BoardItem] {
        var result: [BoardItem] = []
        var visited: Set<UUID> = [id]
        var next = item(id: id)?.parentID
        while let parentID = next, let parent = item(id: parentID), parent.kind == .folder, visited.insert(parentID).inserted {
            result.append(parent)
            next = parent.parentID
        }
        return result
    }

    /// Tudo que está dentro da pasta, em qualquer nível, sem ela. Vai de nível em nível e, dentro de cada pasta,
    /// na ordem de `children(of:)`. Termina mesmo com ciclo nos dados.
    public func descendants(of folderID: UUID) -> [BoardItem] {
        descendants(of: folderID, byParent: childrenByParent())
    }

    /// Quantas pastas há acima do cartão (0 = solto no mural). O nível de uma pasta é a profundidade dela mais 1.
    public func depth(of id: UUID) -> Int {
        ancestors(of: id).count
    }

    /// As pastas para onde o cartão pode ir agora, ordenadas pelo caminho. Ficam de fora o próprio cartão, o que há dentro dele
    /// (se for pasta), a pasta onde ele já está e as que fariam a pasta movida passar de `maximumFolderDepth` níveis.
    public func folderDestinations(for id: UUID) -> [FolderDestination] {
        guard let moving = item(id: id) else { return [] }
        let byParent = childrenByParent()
        // Níveis que a pasta movida ocupa com tudo que tem dentro; cartão que não é pasta não conta nível.
        let height = moving.kind == .folder ? folderHeight(of: id, byParent: byParent) : 0
        var destinations: [FolderDestination] = []
        var visited = Set<UUID>()
        // De cima para baixo, levando os títulos do caminho; não entra no próprio cartão.
        var pending = rootItems.filter { $0.kind == .folder }.reversed().map { (folder: $0, parentPath: [String]()) }
        while let (folder, parentPath) = pending.popLast() {
            guard folder.id != id, visited.insert(folder.id).inserted else { continue }
            let path = parentPath + [folder.title]
            if folder.id != moving.parentID, height == 0 || path.count + height <= Self.maximumFolderDepth {
                destinations.append(FolderDestination(id: folder.id, path: path))
            }
            let subfolders = (byParent[folder.id] ?? []).filter { $0.kind == .folder }
            pending.append(contentsOf: subfolders.reversed().map { (folder: $0, parentPath: path) })
        }
        // Títulos iguais ficam na ordem em que foram encontrados.
        return destinations.enumerated()
            .sorted { lhs, rhs in
                let order = lhs.element.title.localizedStandardCompare(rhs.element.title)
                return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
            }
            .map(\.element)
    }

    // MARK: Alterações

    public mutating func add(_ item: BoardItem) {
        items.append(item)
        formatVersion = requiredFormatVersion
    }

    public mutating func update(_ item: BoardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
        formatVersion = requiredFormatVersion
    }

    /// Remove o cartão e, se for pasta, tudo que estiver dentro dela, em qualquer nível.
    /// - Returns: os cartões removidos, na ordem da lista (para apagar os arquivos guardados).
    @discardableResult
    public mutating func remove(id: UUID) -> [BoardItem] {
        let doomed = Set(descendants(of: id).map(\.id)).union([id])
        let removed = items.filter { doomed.contains($0.id) }
        guard !removed.isEmpty else { return [] }
        items.removeAll { doomed.contains($0.id) }
        formatVersion = requiredFormatVersion
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
        formatVersion = requiredFormatVersion
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
        if changed > 0 { formatVersion = requiredFormatVersion }
        return changed
    }

    /// Guarda um cartão, de qualquer nível, dentro de uma pasta, também de qualquer nível. Uma pasta leva consigo tudo que há nela.
    /// A posição do cartão e a ordem da lista não mudam.
    /// - Returns: `false`, sem alterar nada, se o cartão ou a pasta não existem, se são o mesmo, se o destino não é uma pasta
    ///   ou já é o pai, se o destino está dentro do próprio cartão (ciclo) ou se uma pasta movida passaria de
    ///   `maximumFolderDepth` níveis.
    @discardableResult
    public mutating func moveIntoFolder(id: UUID, folderID: UUID) -> Bool {
        guard id != folderID,
            let index = items.firstIndex(where: { $0.id == id }),
            let destination = item(id: folderID), destination.kind == .folder,
            items[index].parentID != folderID
        else { return false }
        let byParent = childrenByParent()
        guard !descendants(of: id, byParent: byParent).contains(where: { $0.id == folderID }) else { return false }
        if items[index].kind == .folder {
            let destinationLevel = depth(of: folderID) + 1
            guard destinationLevel + folderHeight(of: id, byParent: byParent) <= Self.maximumFolderDepth else { return false }
        }
        items[index].parentID = folderID
        formatVersion = requiredFormatVersion
        return true
    }

    /// Tira um cartão de dentro de uma pasta e o solta no mural, no fim da lista (por cima dos outros).
    /// Uma pasta leva consigo tudo que há nela.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe ou já está solto.
    @discardableResult
    public mutating func moveToBoard(id: UUID, at position: BoardPoint) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].parentID != nil else { return false }
        var item = items.remove(at: index)
        item.parentID = nil
        item.position = position
        items.append(item)
        formatVersion = requiredFormatVersion
        return true
    }

    // MARK: Interno

    /// Os filhos de cada pasta, na ordem de `children(of:)`, para percorrer a hierarquia sem varrer a lista a cada passo.
    private func childrenByParent() -> [UUID: [BoardItem]] {
        var grouped: [UUID: [BoardItem]] = [:]
        for item in items {
            if let parentID = item.parentID { grouped[parentID, default: []].append(item) }
        }
        return grouped.mapValues { $0.sorted { $0.createdAt < $1.createdAt } }
    }

    private func descendants(of folderID: UUID, byParent: [UUID: [BoardItem]]) -> [BoardItem] {
        var result: [BoardItem] = []
        var visited: Set<UUID> = [folderID]
        var level = byParent[folderID] ?? []
        while !level.isEmpty {
            var next: [BoardItem] = []
            for child in level where visited.insert(child.id).inserted {
                result.append(child)
                next.append(contentsOf: byParent[child.id] ?? [])
            }
            level = next
        }
        return result
    }

    /// Quantos níveis de pasta a pasta ocupa com as subpastas que tem dentro, contando ela (1 = sem subpastas).
    private func folderHeight(of folderID: UUID, byParent: [UUID: [BoardItem]]) -> Int {
        var height = 0
        var visited: Set<UUID> = [folderID]
        var level = [folderID]
        while !level.isEmpty {
            height += 1
            var next: [UUID] = []
            for id in level {
                for child in byParent[id] ?? [] where child.kind == .folder && visited.insert(child.id).inserted {
                    next.append(child.id)
                }
            }
            level = next
        }
        return height
    }
}

/// Uma pasta para onde um cartão pode ser levado, com o caminho de títulos do mural até ela.
public struct FolderDestination: Identifiable, Hashable, Sendable {
    public let id: UUID
    /// Títulos do mural até a pasta; o último é o da própria pasta.
    public let path: [String]

    public init(id: UUID, path: [String]) {
        self.id = id
        self.path = path
    }

    /// O caminho em uma linha, como "Projetos › Cliente".
    public var title: String { path.joined(separator: " › ") }
}
