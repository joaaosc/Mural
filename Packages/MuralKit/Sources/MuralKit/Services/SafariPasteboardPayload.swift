import Foundation

/// Lê, de forma defensiva, o que o Safari põe na área de transferência ao copiar favoritos, itens da
/// Lista de Leitura e links.
///
/// Esses formatos não são documentados e podem mudar sem aviso: cada valor tem o tipo conferido e o que
/// não bate com o esperado é ignorado, sem travar. Só sobram endereços da web (`http` e `https`), com
/// título, resumo e imagem quando vieram.
public enum SafariPasteboardPayload {
    /// Profundidade máxima lida: as entradas do primeiro nível têm profundidade 0 e as de dentro de uma pasta, uma a mais.
    static let maxDepth = 16
    /// Quantos rascunhos uma leitura devolve, no máximo.
    static let maxDrafts = 1000

    // MARK: Favoritos e Lista de Leitura

    /// Rascunhos de `com.apple.Safari.bookmarkDictionaryList`: uma lista (ou um único dicionário) de favoritos.
    ///
    /// Folhas têm `URLString`, o título em `URIDictionary.title`, o resumo em `previewText` (ou, na Lista de
    /// Leitura, em `ReadingList.PreviewText`) e a imagem em `imageURL`, que só vale se for da web. Pastas
    /// guardam as entradas em `Children` e são percorridas até a profundidade 16, até 1000 rascunhos.
    public static func drafts(fromBookmarkList plist: Any) -> [LinkDraft] {
        var drafts: [LinkDraft] = []
        if let entries = plist as? [Any] {
            collect(entries, depth: 0, into: &drafts)
        } else if let entry = plist as? [String: Any] {
            collect([entry], depth: 0, into: &drafts)
        }
        return drafts
    }

    private static func collect(_ entries: [Any], depth: Int, into drafts: inout [LinkDraft]) {
        for case let entry as [String: Any] in entries {
            guard drafts.count < maxDrafts else { return }
            if let draft = bookmarkDraft(entry) { drafts.append(draft) }
            if depth < maxDepth, let children = entry["Children"] as? [Any] {
                collect(children, depth: depth + 1, into: &drafts)
            }
        }
    }

    /// O rascunho de uma folha; `nil` para pastas, atalhos e entradas sem endereço da web.
    private static func bookmarkDraft(_ entry: [String: Any]) -> LinkDraft? {
        guard let url = webURL(entry["URLString"]) else { return nil }
        let title = (entry["URIDictionary"] as? [String: Any]).flatMap { text($0["title"]) }
        let readingList = entry["ReadingList"] as? [String: Any]
        let summary = text(entry["previewText"]) ?? text(readingList?["PreviewText"])
        return LinkDraft(url: url, title: title, summary: summary, imageURL: webURL(entry["imageURL"]))
    }

    // MARK: Endereços com títulos

    /// Rascunhos de `WebURLsWithTitlesPboardType`: `[[endereços], [títulos]]`, com o título na mesma posição
    /// do endereço. Título ausente ou vazio fica sem título.
    public static func drafts(fromURLsWithTitles plist: Any) -> [LinkDraft] {
        guard let columns = plist as? [Any], let addresses = columns.first as? [Any] else { return [] }
        let titles = columns.count > 1 ? (columns[1] as? [Any] ?? []) : []
        var drafts: [LinkDraft] = []
        for (index, address) in addresses.enumerated() {
            guard drafts.count < maxDrafts else { break }
            guard let url = webURL(address) else { continue }
            drafts.append(LinkDraft(url: url, title: index < titles.count ? text(titles[index]) : nil))
        }
        return drafts
    }

    // MARK: Apoio

    /// O endereço da web escrito no texto; `nil` para qualquer outro valor.
    private static func webURL(_ value: Any?) -> URL? {
        (value as? String).flatMap { WebLink.url(from: $0) }
    }

    /// O texto sem espaços e quebras nas pontas; `nil` se não for texto ou ficar vazio.
    private static func text(_ value: Any?) -> String? {
        guard let trimmed = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
