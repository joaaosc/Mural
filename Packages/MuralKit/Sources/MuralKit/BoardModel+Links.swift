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

    // MARK: Prévias

    /// Nomes dos arquivos de prévia (imagem e ícone) que algum cartão do mural usa.
    ///
    /// É o que `LinkPreviewFiles.sweep(keeping:minimumAge:now:)` precisa para apagar o resto.
    public var referencedLinkPreviewFiles: Set<String> {
        var names = Set<String>()
        for link in board.items.compactMap(\.link) {
            if let image = link.previewImageFile { names.insert(image) }
            if let icon = link.iconFile { names.insert(icon) }
        }
        return names
    }

    /// Pedidos de prévia para os cartões de link indicados, na ordem recebida e sem repetir cartão.
    ///
    /// Ficam de fora ids que não existem, cartões de outro tipo e os que `LinkPreviewPolicy.shouldFetch`
    /// manda esperar (prévia pronta ou falha recente). Com `force` entram todos os cartões de link, como
    /// ao pedir para atualizar a prévia. `previousAttempts` vem do estado `.failed` do cartão.
    public func linkPreviewRequests(for itemIDs: [UUID], now: Date = .now, force: Bool = false) -> [LinkPreviewRequest] {
        var seen = Set<UUID>()
        var requests: [LinkPreviewRequest] = []
        for id in itemIDs where seen.insert(id).inserted {
            guard let item = board.item(id: id), item.kind == .link, let link = item.link, WebLink.isWeb(link.url),
                force || LinkPreviewPolicy.shouldFetch(link.preview, now: now)
            else { continue }
            var attempts = 0
            if case .failed(_, let count) = link.preview { attempts = count }
            requests.append(
                LinkPreviewRequest(itemID: id, url: link.url, remoteImageURL: link.remoteImageURL, previousAttempts: attempts))
        }
        return requests
    }

    /// Aplica os resultados das buscas de prévia aos cartões de link e grava uma vez se algo mudou.
    ///
    /// Resultados de cartões apagados ou que não são de link são ignorados. Numa busca bem-sucedida
    /// (`.ready`) o título da página, o nome do site e os arquivos novos substituem os antigos, mas um valor
    /// vazio nunca apaga o que já existe. O resumo e a imagem remota só entram se o cartão ainda não tiver
    /// um, porque o que veio do Safari ao arrastar tem prioridade. O título do cartão só vira o título da
    /// página enquanto for o provisório (o host do endereço); depois de renomeado, não é mexido.
    /// Numa falha (`.failed`) só o estado muda.
    public func applyLinkPreviews(_ updates: [LinkPreviewUpdate]) {
        guard !updates.isEmpty else { return }
        var updated = board
        var indices: [UUID: Int] = [:]
        for (offset, item) in updated.items.enumerated() where item.kind == .link {
            indices[item.id] = offset
        }

        var changed = false
        for update in updates {
            guard let index = indices[update.itemID] else { continue }
            let merged = Self.merging(update, into: updated.items[index])
            if merged != updated.items[index] {
                updated.items[index] = merged
                changed = true
            }
        }

        guard changed else { return }
        board = updated
        persist()
    }

    /// Cartão de link com o resultado da busca já mesclado. Cartão sem dados de link volta como está.
    private static func merging(_ update: LinkPreviewUpdate, into item: BoardItem) -> BoardItem {
        guard var link = item.link else { return item }
        var item = item
        link.preview = update.state
        guard case .ready = update.state else {
            item.link = link
            return item
        }

        if let pageTitle = nonBlank(update.pageTitle) {
            link.pageTitle = pageTitle
            if item.title == WebLink.displayHost(of: link.url) { item.title = pageTitle }
        }
        if let siteName = nonBlank(update.siteName) { link.siteName = siteName }
        if nonBlank(link.summary) == nil, let summary = nonBlank(update.summary) { link.summary = summary }
        if link.remoteImageURL == nil, let imageURL = update.remoteImageURL, WebLink.isWeb(imageURL) { link.remoteImageURL = imageURL }
        if let file = update.previewImageFile { link.previewImageFile = file }
        if let file = update.iconFile { link.iconFile = file }
        item.link = link
        return item
    }

    /// O texto sem espaços e quebras nas pontas; `nil` se for `nil` ou ficar vazio.
    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
