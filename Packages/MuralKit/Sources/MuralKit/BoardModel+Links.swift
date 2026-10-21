import Foundation

@MainActor
extension BoardModel {
    /// Cria um cartão de link para cada rascunho com endereço da web válido e grava uma vez ao final.
    ///
    /// Rascunhos inválidos são ignorados, e repetidos dentro do mesmo lote (mesma `WebLink.dedupeKey`)
    /// viram um cartão só. O mural não é consultado: o mesmo link pode entrar de novo em outra pasta.
    /// O resumo e a imagem do rascunho vão para a prévia do cartão; resumo em branco e imagem que
    /// não seja `http` ou `https` são descartados.
    /// Solto no mural, o cartão ocupa a primeira vaga livre; com `point`, o primeiro fica centralizado
    /// nele e os seguintes em cascata. Dentro de uma pasta a posição não importa.
    /// - Returns: os cartões criados, na ordem do lote.
    @discardableResult
    public func importLinks(_ drafts: [LinkDraft], into parentID: UUID? = nil, at point: BoardPoint? = nil) -> [BoardItem] {
        let size = BoardLayout.cardSize(for: .link)
        // A origem da cascata já passa por `clamped`: perto da borda ela não colapsa em (0, 0).
        let cascadeOrigin = point.map {
            BoardLayout.clamped(BoardPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2))
        }
        let cascadeStep = 24.0
        let now = Date.now
        var seen = Set<String>()
        var created: [BoardItem] = []

        for draft in drafts where WebLink.isWeb(draft.url) {
            guard seen.insert(WebLink.dedupeKey(for: draft.url)).inserted else { continue }
            let index = Double(created.count)
            let title = draft.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let summary = draft.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let imageURL = draft.imageURL.flatMap { WebLink.isWeb($0) ? $0 : nil }
            var item = BoardItem(
                kind: .link,
                title: title.isEmpty ? WebLink.displayHost(of: draft.url) : title,
                createdAt: now.addingTimeInterval(index * 0.001),
                parentID: parentID,
                link: LinkInfo(url: draft.url, summary: summary.isEmpty ? nil : summary, remoteImageURL: imageURL)
            )
            if parentID == nil, let cascadeOrigin {
                // Posição pedida pelo usuário: entra direto, porque `insert` a trocaria por uma vaga livre.
                item.position = BoardLayout.clamped(
                    BoardPoint(x: cascadeOrigin.x + index * cascadeStep, y: cascadeOrigin.y + index * cascadeStep))
                board.add(item)
                created.append(item)
            } else {
                created.append(insert(item))
            }
        }

        if !created.isEmpty { persist() }
        return created
    }
}
