import Foundation

extension Board {
    /// Conserta o que duas pessoas mexendo ao mesmo tempo no mural podem deixar quebrado. O conserto é determinístico: dois Macs que
    /// consertam a mesma entrada chegam ao mesmo resultado, seja qual for a ordem da lista.
    ///
    /// - Pai ausente ou que não é pasta: o cartão vai para o mural.
    /// - Ciclo de pastas: em cada ciclo, a pasta de menor `id.uuidString` vai para o mural, com o que tem dentro.
    /// - Pasta além de `maximumFolderDepth` níveis, de cima para baixo: vai para o mural com o que tem dentro.
    /// - Lugar livre de pasta (`folderPosition`) em cartão que não é post-it ou está solto no mural: é apagado.
    ///
    /// Quem vai para o mural fica sem pasta nem lugar livre e ganha a primeira posição livre (`BoardLayout.freePosition`), um de cada
    /// vez, do mais antigo ao mais novo (empate: `id.uuidString`), sem mudar o lugar na lista. Se algo mudou, `formatVersion` passa a
    /// ser `requiredFormatVersion`.
    /// - Returns: os cartões levados ao mural, na ordem em que ganharam posição; vazio se nenhum precisou ir.
    @discardableResult
    public mutating func repairStructure() -> [UUID] {
        var moved: [UUID] = []
        for index in indicesToMoveToBoard() {
            // A posição vem antes de soltar o cartão: ele ainda está na pasta, então não conta como obstáculo para si mesmo. A vaga
            // tem o tamanho que o cartão tem, como em `BoardModel.moveToBoard`: um post-it redimensionado não cai sobre os vizinhos.
            let position = BoardLayout.freePosition(for: items[index], avoiding: rootItems)
            items[index].position = position
            items[index].parentID = nil
            items[index].folderPosition = nil
            moved.append(items[index].id)
        }

        var clearedPlaces = false
        for index in items.indices where items[index].folderPosition != nil {
            guard items[index].kind != .sticky || items[index].parentID == nil else { continue }
            items[index].folderPosition = nil
            clearedPlaces = true
        }

        if !moved.isEmpty || clearedPlaces { formatVersion = requiredFormatVersion }
        return moved
    }

    /// As posições, na lista, dos cartões que a hierarquia obriga a ir para o mural, do mais antigo ao mais novo. Quem decide é só a
    /// estrutura (os pais e as datas de criação): a ordem da lista não muda o resultado. Cartão com id repetido (dado corrompido)
    /// conta só na primeira vez, como em `item(id:)`.
    private func indicesToMoveToBoard() -> [Int] {
        var firstIndex: [UUID: Int] = [:]
        for (index, item) in items.enumerated() where firstIndex[item.id] == nil { firstIndex[item.id] = index }
        let unique = items.indices.filter { firstIndex[items[$0].id] == $0 }

        // Pai de cada cartão como ficará, sem os que vão para o mural.
        var parentOf: [UUID: UUID] = [:]
        var toBoard = Set<UUID>()

        // Pai ausente ou que não é pasta.
        for index in unique {
            let item = items[index]
            guard let parentID = item.parentID else { continue }
            if let parent = firstIndex[parentID], items[parent].kind == .folder {
                parentOf[item.id] = parentID
            } else {
                toBoard.insert(item.id)
            }
        }

        // Ciclo de pastas: cada pasta segue os pais até chegar ao mural, a uma pasta já resolvida ou a uma do caminho atual (ciclo).
        var resolved: [UUID: Bool] = [:]  // falso: no caminho atual; verdadeiro: já resolvida
        for index in unique where items[index].kind == .folder {
            var path: [UUID] = []
            var current: UUID? = items[index].id
            while let folder = current, resolved[folder] == nil {
                resolved[folder] = false
                path.append(folder)
                current = parentOf[folder]
            }
            if let folder = current, resolved[folder] == false, let start = path.firstIndex(of: folder),
                let smallest = path[start...].min(by: { $0.uuidString < $1.uuidString })
            {
                parentOf[smallest] = nil
                toBoard.insert(smallest)
            }
            for folder in path { resolved[folder] = true }
        }

        // Profundidade, de cima para baixo: a pasta que passa do último nível vira o nível 1 do mural e leva o que tem dentro, e as
        // de baixo contam os níveis a partir dela. O que se faz com cada pasta só depende das de cima, então a ordem em que a
        // hierarquia é percorrida não muda o resultado.
        var subfolders: [UUID: [UUID]] = [:]
        var pending: [(id: UUID, level: Int)] = []
        for index in unique where items[index].kind == .folder {
            let folderID = items[index].id
            if let parentID = parentOf[folderID] {
                subfolders[parentID, default: []].append(folderID)
            } else {
                pending.append((folderID, 1))
            }
        }
        while let (folderID, level) = pending.popLast() {
            for child in subfolders[folderID] ?? [] {
                if level + 1 > Board.maximumFolderDepth {
                    toBoard.insert(child)
                    pending.append((child, 1))
                } else {
                    pending.append((child, level + 1))
                }
            }
        }

        return toBoard.compactMap { firstIndex[$0] }.sorted { Board.isCreatedBefore(items[$0], items[$1]) }
    }
}
