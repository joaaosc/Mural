import Foundation

@MainActor
extension BoardModel {
    /// Cria um cartão de contato para cada pessoa e grava uma vez ao final, se criou algo.
    ///
    /// Repetidos dentro do mesmo lote (mesma `ContactSnapshot.dedupeKey`) viram um cartão só. O mural não é consultado: a mesma
    /// pessoa pode entrar de novo em outra pasta. O título do cartão é o nome de exibição.
    /// - Returns: os cartões criados, na ordem do lote.
    @discardableResult
    public func importContacts(
        _ snapshots: [ContactSnapshot], into parentID: UUID? = nil, at anchor: BoardPoint? = nil
    ) -> [BoardItem] {
        guard !isReadOnly else { return refuseEdit([]) }
        let now = Date.now
        var seen = Set<String>()
        var pending: [BoardItem] = []
        for snapshot in snapshots where seen.insert(snapshot.dedupeKey).inserted {
            let item = BoardItem(
                kind: .contact,
                title: snapshot.displayName,
                createdAt: now.addingTimeInterval(Double(pending.count) * 0.001),
                parentID: parentID,
                contact: snapshot
            )
            pending.append(item)
        }
        let created = insertBatch(pending, anchor: anchor)
        if !created.isEmpty { persist() }
        return created
    }

    /// Guarda o nome do arquivo da foto reduzida no contato (parte local de cada Mac).
    ///
    /// Vale mesmo num mural só para ver: a foto é deste Mac e não muda o que as outras pessoas veem.
    /// - Returns: `false`, sem gravar, se o cartão não é de contato ou o nome já era esse.
    @discardableResult
    public func setContactThumbnail(_ itemID: UUID, file: String?) -> Bool {
        guard var item = item(id: itemID), item.kind == .contact, var contact = item.contact, contact.thumbnailFile != file
        else { return false }
        contact.thumbnailFile = file
        item.contact = contact
        board.update(item)
        persist()
        return true
    }
}
