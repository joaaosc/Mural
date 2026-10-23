import Foundation

@MainActor
extension BoardModel {
    /// Todos os cartões de música do mural, de qualquer nível.
    public var musicItems: [BoardItem] { board.items.filter { $0.kind == .music } }

    /// Cria um cartão de música para cada item e grava uma vez ao final, se criou algo.
    ///
    /// Repetidos dentro do mesmo lote (mesma `MusicSnapshot.dedupeKey`) viram um cartão só. O mural não
    /// é consultado: o mesmo item pode entrar de novo em outra pasta. O título do cartão é o do item.
    /// - Returns: os cartões criados, na ordem do lote.
    @discardableResult
    public func importMusic(
        _ snapshots: [MusicSnapshot], into parentID: UUID? = nil, at anchor: BoardPoint? = nil
    ) -> [BoardItem] {
        guard !isReadOnly else { return refuseEdit([]) }
        let now = Date.now
        var seen = Set<String>()
        var created: [BoardItem] = []
        for snapshot in snapshots where seen.insert(snapshot.dedupeKey).inserted {
            let item = BoardItem(
                kind: .music,
                title: snapshot.title,
                createdAt: now.addingTimeInterval(Double(created.count) * 0.001),
                parentID: parentID,
                music: snapshot
            )
            created.append(insert(item, anchor: anchor))
        }
        if !created.isEmpty { persist() }
        return created
    }

    /// Troca o estado guardado da música; o título do cartão acompanha.
    ///
    /// Num mural só para ver (`isReadOnly`) entram só as partes deste Mac, a capa e o id da biblioteca
    /// (`SharedFieldPolicy.preservingLocalFields(of:in:)`); o resto do cartão fica como está, sem aviso.
    /// - Returns: `false`, sem gravar, se o cartão não é de música ou nada mudou.
    @discardableResult
    public func updateMusic(_ itemID: UUID, with snapshot: MusicSnapshot) -> Bool {
        guard var item = board.item(id: itemID), item.kind == .music,
            item.music != snapshot || (item.music?.title != snapshot.title && item.title == item.music?.title)
        else { return false }
        let current = item
        let previousTitle = item.music?.title
        item.music = snapshot
        if item.title == previousTitle { item.title = snapshot.title }
        if isReadOnly {
            item = SharedFieldPolicy.preservingLocalFields(of: item, in: current)
            guard item != current else { return false }
        }
        board.update(item)
        persist()
        return true
    }
}
