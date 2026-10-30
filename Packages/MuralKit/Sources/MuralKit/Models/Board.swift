import Foundation

/// O mural inteiro: todos os cartões, soltos ou dentro de pastas.
public struct Board: Codable, Equatable, Sendable {
    /// A versão mais nova do formato que esta build lê. Uma build recusa abrir um mural de versão maior
    /// que a sua (`BoardRepositoryError.futureBoardFormat`).
    /// - 2: pasta dentro de pasta (a versão 1 só tinha pastas soltas no mural).
    /// - 3: cartão de link.
    /// - 4: cor nos cartões (`BoardItem.colorTag`).
    /// - 5: imagem colada em nota (`BoardItem.attachments`).
    /// - 6: cartão de lembrete.
    /// - 7: textos livres diretamente no mural.
    /// - 8: cartão de música (Apple Music).
    /// - 9: post-it num lugar livre dentro da pasta (`BoardItem.folderPosition`).
    /// - 10: legenda separada do corpo (`BoardItem.caption`).
    /// - 11: tamanho escolhido para post-it e texto livre (`BoardItem.size`, `BoardFreeText.size`).
    /// - 12: tamanho escolhido para imagens (`BoardItem.size`).
    /// - 13: cartão embutido numa nota (`NoteAttachment.card`).
    public static let currentFormatVersion = 13

    /// Quantos níveis de pasta podem ficar uns dentro dos outros. Uma pasta solta no mural é o nível 1;
    /// uma pasta nunca fica abaixo do nível 8. Cartões que não são pasta cabem em qualquer pasta.
    public static let maximumFolderDepth = 8

    /// Versão do formato que o conteúdo exigia quando o mural foi gravado. Toda alteração de fato grava
    /// `requiredFormatVersion`: um mural antigo só muda de versão junto com uma mudança real (e, portanto,
    /// com uma revisão nova), e um mural que não usa nada novo continua abrindo nas builds anteriores.
    public var formatVersion: Int
    public var items: [BoardItem]
    /// Textos livres diretamente no mural. Ausente em murais antigos.
    public var freeTexts: [BoardFreeText]

    private enum CodingKeys: String, CodingKey {
        case formatVersion, items, freeTexts
    }

    public init(items: [BoardItem] = [], freeTexts: [BoardFreeText] = []) {
        self.items = items
        self.freeTexts = freeTexts
        self.formatVersion = Self.minimumFormatVersion(for: items, freeTexts: freeTexts)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        self.items = try container.decode([BoardItem].self, forKey: .items)
        self.freeTexts = try container.decodeIfPresent([BoardFreeText].self, forKey: .freeTexts) ?? []
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(items, forKey: .items)
        // An empty collection carries no new content and is omitted so old-format
        // boards keep their previous shape and required version.
        if !freeTexts.isEmpty {
            try container.encode(freeTexts, forKey: .freeTexts)
        }
    }

    /// A menor versão do formato que guarda este conteúdo sem perder nada: numa build anterior a ela, o mural
    /// não abriria ou perderia ao gravar o que ela não conhece. Cada versão nova do formato precisa de uma regra aqui.
    public var requiredFormatVersion: Int { Self.minimumFormatVersion(for: items, freeTexts: freeTexts) }

    static func minimumFormatVersion(for items: [BoardItem]) -> Int {
        var version = 1
        if items.contains(where: { $0.kind == .folder && $0.parentID != nil }) { version = max(version, 2) }
        if items.contains(where: { $0.kind == .link }) { version = max(version, 3) }
        if items.contains(where: { $0.colorTag != nil }) { version = max(version, 4) }
        if items.contains(where: { !($0.attachments ?? []).isEmpty }) { version = max(version, 5) }
        if items.contains(where: { $0.kind == .reminder }) { version = max(version, 6) }
        if items.contains(where: { $0.kind == .music }) { version = max(version, 8) }
        if items.contains(where: { $0.folderPosition != nil }) { version = max(version, 9) }
        if items.contains(where: { $0.caption != nil }) { version = max(version, 10) }
        if items.contains(where: { $0.size != nil }) { version = max(version, 11) }
        if items.contains(where: { $0.kind == .image && $0.size != nil }) { version = max(version, 12) }
        if items.contains(where: { ($0.attachments ?? []).contains(where: \.isCard) }) { version = max(version, 13) }
        return version
    }

    static func minimumFormatVersion(for items: [BoardItem], freeTexts: [BoardFreeText]) -> Int {
        var version = minimumFormatVersion(for: items)
        if !freeTexts.isEmpty { version = max(version, 7) }
        if freeTexts.contains(where: { $0.size != nil }) { version = max(version, 11) }
        return version
    }

    /// Cartões soltos no mural (sem pasta).
    public var rootItems: [BoardItem] {
        items.filter { $0.parentID == nil }
    }

    /// Cartões dentro de uma pasta, na ordem de criação (em empate de data, pelo `id.uuidString`).
    public func children(of folderID: UUID) -> [BoardItem] {
        items.filter { $0.parentID == folderID }.sorted(by: Self.isCreatedBefore)
    }

    /// A ordem de criação: pela data e, em empate, pelo `id.uuidString`. Datas iguais acontecem, e sem o desempate cada Mac
    /// poderia ordenar os cartões de um jeito, conforme a ordem da própria lista.
    static func isCreatedBefore(_ lhs: BoardItem, _ rhs: BoardItem) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Post-its soltos num lugar livre da pasta, na ordem da lista: o último fica por cima.
    public func placedStickies(in folderID: UUID) -> [BoardItem] {
        items.filter { $0.parentID == folderID && $0.isPlacedInFolder }
    }

    public func item(id: UUID) -> BoardItem? {
        items.first { $0.id == id }
    }

    public func freeText(id: UUID) -> BoardFreeText? {
        freeTexts.first { $0.id == id }
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

    /// Variante interna que reutiliza um índice de hierarquia preparado pelo `BoardModel`.
    func descendantCount(of folderID: UUID, byParent: [UUID: [BoardItem]]) -> Int {
        var count = 0
        var visited: Set<UUID> = [folderID]
        var level = byParent[folderID] ?? []
        while !level.isEmpty {
            var next: [BoardItem] = []
            next.reserveCapacity(level.count)
            for child in level where visited.insert(child.id).inserted {
                count += 1
                next.append(contentsOf: byParent[child.id] ?? [])
            }
            level = next
        }
        return count
    }

    /// Quantas pastas há acima do cartão (0 = solto no mural). O nível de uma pasta é a profundidade dela mais 1.
    public func depth(of id: UUID) -> Int {
        ancestors(of: id).count
    }

    /// A cadeia de pais chega ao mural passando só por pastas e sem passar de `Board.maximumFolderDepth` níveis
    /// (uma pasta ocupa um nível; um cartão que não é pasta cabe em qualquer pasta). Um ciclo nunca chega ao mural
    /// e acaba no limite de níveis.
    static func hasValidParentChain(_ item: BoardItem, in itemsByID: [UUID: BoardItem]) -> Bool {
        var foldersAbove = 0
        var next = item.parentID
        while let parentID = next {
            guard let parent = itemsByID[parentID], parent.kind == .folder else { return false }
            foldersAbove += 1
            guard foldersAbove <= maximumFolderDepth else { return false }
            next = parent.parentID
        }
        return item.kind != .folder || foldersAbove < maximumFolderDepth
    }

    /// As pastas para onde o cartão pode ir agora, ordenadas pelo caminho. Ficam de fora o próprio cartão, o que há dentro dele
    /// (se for pasta), a pasta onde ele já está e as que fariam a pasta movida passar de `maximumFolderDepth` níveis.
    public func folderDestinations(for id: UUID) -> [FolderDestination] {
        folderDestinations(for: id, byParent: childrenByParent(), rootItems: rootItems)
    }

    /// Variante interna que reutiliza um índice de hierarquia preparado pelo `BoardModel`.
    /// Mantém a variante pública pura para snapshots independentes.
    func folderDestinations(
        for id: UUID,
        byParent: [UUID: [BoardItem]],
        rootItems: [BoardItem]
    ) -> [FolderDestination] {
        guard let moving = item(id: id) else { return [] }
        return folderDestinations(for: id, moving: moving, byParent: byParent, rootItems: rootItems)
    }

    /// Variante interna que recebe o cartão já localizado pelo índice do `BoardModel`, evitando
    /// repetir uma busca linear no array de itens ao montar o menu de movimento.
    func folderDestinations(
        for id: UUID,
        moving: BoardItem,
        byParent: [UUID: [BoardItem]],
        rootItems: [BoardItem]
    ) -> [FolderDestination] {
        folderDestinations(
            for: id,
            moving: moving,
            byParent: byParent,
            rootFolderItems: rootItems.filter { $0.kind == .folder })
    }

    /// Variante interna que reutiliza também as pastas raiz já filtradas pelo `BoardModel`.
    func folderDestinations(
        for id: UUID,
        moving: BoardItem,
        byParent: [UUID: [BoardItem]],
        rootFolderItems: [BoardItem]
    ) -> [FolderDestination] {
        guard moving.id == id else { return [] }
        // Níveis que a pasta movida ocupa com tudo que tem dentro; cartão que não é pasta não conta nível.
        let height = moving.kind == .folder ? folderHeight(of: id, byParent: byParent) : 0
        var destinations: [FolderDestination] = []
        var visited = Set<UUID>()
        // De cima para baixo, levando os títulos do caminho; não entra no próprio cartão.
        var pending = rootFolderItems.reversed().map { (folder: $0, parentPath: [String]()) }
        while let (folder, parentPath) = pending.popLast() {
            guard folder.id != id, visited.insert(folder.id).inserted else { continue }
            let path = parentPath + [folder.title]
            if folder.id != moving.parentID, height == 0 || path.count + height <= Self.maximumFolderDepth {
                destinations.append(FolderDestination(id: folder.id, path: path))
            }
            for child in (byParent[folder.id] ?? []).reversed() where child.kind == .folder {
                pending.append((folder: child, parentPath: path))
            }
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

    public mutating func add(_ freeText: BoardFreeText) {
        var placed = freeText
        placed.position = BoardLayout.clamped(placed.position)
        placed.size = BoardLayout.normalizedFreeTextSize(placed.size)
        freeTexts.append(placed)
        formatVersion = requiredFormatVersion
    }

    public mutating func update(_ freeText: BoardFreeText) {
        guard let index = freeTexts.firstIndex(where: { $0.id == freeText.id }) else { return }
        var updated = freeText
        updated.text = BoardFreeText.normalized(updated.text)
        updated.position = BoardLayout.clamped(updated.position)
        updated.size = BoardLayout.normalizedFreeTextSize(updated.size)
        freeTexts[index] = updated
        formatVersion = requiredFormatVersion
    }

    @discardableResult
    public mutating func removeFreeText(id: UUID) -> Bool {
        guard let index = freeTexts.firstIndex(where: { $0.id == id }) else { return false }
        freeTexts.remove(at: index)
        formatVersion = requiredFormatVersion
        return true
    }

    @discardableResult
    public mutating func moveFreeText(id: UUID, to position: BoardPoint) -> Bool {
        guard let index = freeTexts.firstIndex(where: { $0.id == id }) else { return false }
        freeTexts[index].position = BoardLayout.clamped(position)
        formatVersion = requiredFormatVersion
        return true
    }

    /// Muda o tamanho de um texto livre. O tamanho é normalizado (`BoardLayout.normalizedFreeTextSize`): `nil`, ou um tamanho igual
    /// ao padrão, devolve o texto ao quadrado padrão, e o mural deixa de exigir a versão 11 se nenhum outro elemento tiver tamanho.
    /// - Returns: `false`, sem alterar nada, se o texto não existe ou já tinha esse tamanho.
    @discardableResult
    public mutating func resizeFreeText(id: UUID, to size: BoardSize?) -> Bool {
        guard let index = freeTexts.firstIndex(where: { $0.id == id }) else { return false }
        let normalized = BoardLayout.normalizedFreeTextSize(size)
        guard freeTexts[index].size != normalized else { return false }
        freeTexts[index].size = normalized
        formatVersion = requiredFormatVersion
        return true
    }

    /// Muda posição e tamanho de um texto livre numa só alteração (arrastar um canto que não é o de baixo à direita). Valem as
    /// regras de `resizeFreeText(id:to:)` para o tamanho e as de `moveFreeText(id:to:)` para a posição.
    /// - Returns: `false`, sem alterar nada, se o texto não existe ou já estava assim.
    @discardableResult
    public mutating func setFreeTextFrame(id: UUID, origin: BoardPoint, size: BoardSize?) -> Bool {
        guard let index = freeTexts.firstIndex(where: { $0.id == id }) else { return false }
        let position = BoardLayout.clamped(origin)
        let normalized = BoardLayout.normalizedFreeTextSize(size)
        guard freeTexts[index].position != position || freeTexts[index].size != normalized else { return false }
        freeTexts[index].position = position
        freeTexts[index].size = normalized
        formatVersion = requiredFormatVersion
        return true
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
        let doomed = removalIDs(startingAt: id)
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

    /// Muda o tamanho de um cartão que pode mudar de tamanho (`BoardLayout.isResizable`). O tamanho é
    /// normalizado (`BoardLayout.normalizedSize(_:for:)`): `nil`, ou um tamanho igual ao padrão do tipo, devolve o cartão ao padrão,
    /// e o mural deixa de exigir a versão 11 se nenhum outro elemento tiver tamanho. A ordem da lista não muda: o cartão não vai
    /// para cima dos outros. Um post-it guardado numa pasta também aceita o tamanho, que só vale quando ele volta ao mural.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe, não muda de tamanho ou já tinha esse tamanho.
    @discardableResult
    public mutating func resize(id: UUID, to size: BoardSize?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), BoardLayout.isResizable(items[index].kind) else { return false }
        let normalized = BoardLayout.normalizedSize(size, for: items[index].kind)
        guard items[index].size != normalized else { return false }
        items[index].size = normalized
        formatVersion = requiredFormatVersion
        return true
    }

    /// Muda posição e tamanho de um cartão solto numa só alteração (arrastar um canto que não é o de baixo à direita). O tamanho
    /// é normalizado como em `resize(id:to:)` e a posição é arredondada e presa a 0 como em `BoardModel.move`, mas a ordem da lista
    /// não muda: o cartão não vai para cima dos outros.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe, não muda de tamanho, está numa pasta ou já estava assim.
    @discardableResult
    public mutating func setFrame(id: UUID, origin: BoardPoint, size: BoardSize?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].parentID == nil,
            BoardLayout.isResizable(items[index].kind)
        else { return false }
        let position = BoardLayout.clamped(origin)
        let normalized = BoardLayout.normalizedSize(size, for: items[index].kind)
        guard items[index].position != position || items[index].size != normalized else { return false }
        items[index].position = position
        items[index].size = normalized
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

    /// Põe um post-it de pasta num lugar livre dela (`BoardItem.folderPosition`) e o leva para o fim da lista, que a pasta
    /// desenha por cima dos outros post-its soltos. O lugar é arredondado, `y` nunca fica acima do topo e valores
    /// inválidos (NaN, infinito) viram 0.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe, não é post-it ou está solto no mural.
    @discardableResult
    public mutating func placeInFolder(id: UUID, at position: BoardPoint) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind == .sticky, items[index].parentID != nil else {
            return false
        }
        var item = items.remove(at: index)
        item.folderPosition = Self.folderPlacement(position)
        items.append(item)
        formatVersion = requiredFormatVersion
        return true
    }

    /// Guarda um cartão, de qualquer nível, dentro de uma pasta, também de qualquer nível. Uma pasta leva consigo tudo que há nela.
    /// A posição do cartão no mural e a ordem da lista não mudam; o lugar livre que um post-it tinha na pasta antiga é esquecido
    /// (na nova, ele entra nas colunas).
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
        items[index].folderPosition = nil
        formatVersion = requiredFormatVersion
        return true
    }

    /// Tira um cartão de dentro de uma pasta e o solta no mural, no fim da lista (por cima dos outros).
    /// Uma pasta leva consigo tudo que há nela. O lugar livre que um post-it tinha na pasta é esquecido.
    /// - Returns: `false`, sem alterar nada, se o cartão não existe ou já está solto.
    @discardableResult
    public mutating func moveToBoard(id: UUID, at position: BoardPoint) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].parentID != nil else { return false }
        var item = items.remove(at: index)
        item.parentID = nil
        item.position = position
        item.folderPosition = nil
        items.append(item)
        formatVersion = requiredFormatVersion
        return true
    }

    // MARK: Interno

    /// O lugar na pasta como é guardado: arredondado, com `x` e `y` inválidos (NaN, infinito) em 0 e `y` nunca acima do topo.
    private static func folderPlacement(_ point: BoardPoint) -> BoardPoint {
        let x = point.x.rounded()
        let y = point.y.rounded()
        // `!= 0` e `> 0` também trocam -0 por 0, para o arquivo nunca gravar "-0".
        return BoardPoint(x: x.isFinite && x != 0 ? x : 0, y: y.isFinite && y > 0 ? y : 0)
    }

    /// Os filhos de cada pasta, na ordem de `children(of:)`, para percorrer a hierarquia sem varrer a lista a cada passo.
    private func childrenByParent() -> [UUID: [BoardItem]] {
        var grouped: [UUID: [BoardItem]] = [:]
        for item in items {
            if let parentID = item.parentID { grouped[parentID, default: []].append(item) }
        }
        return grouped.mapValues { $0.sorted(by: Self.isCreatedBefore) }
    }

    /// IDs usados somente pela remoção. A ordem dos filhos não é observável nesse caminho:
    /// `remove(id:)` devolve os cartões filtrados na ordem original de `items`. Evitar ordenar e
    /// copiar `BoardItem` reduz o trabalho e as alocações ao apagar uma pasta grande.
    private func removalIDs(startingAt id: UUID) -> Set<UUID> {
        var childrenByParent: [UUID: [UUID]] = [:]
        childrenByParent.reserveCapacity(items.count)
        for item in items {
            guard let parentID = item.parentID else { continue }
            childrenByParent[parentID, default: []].append(item.id)
        }

        var doomed: Set<UUID> = [id]
        var queue = childrenByParent[id] ?? []
        var cursor = 0
        while cursor < queue.count {
            let childID = queue[cursor]
            cursor += 1
            guard doomed.insert(childID).inserted else { continue }
            queue.append(contentsOf: childrenByParent[childID] ?? [])
        }
        return doomed
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
