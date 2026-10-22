import AppKit
import Foundation
import LinkPresentation
import MuralKit

/// Lê os links da área de transferência do ⌘V, dos dados mais ricos aos mais pobres.
///
/// Os tipos do Safari não são documentados: cada leitura é defensiva e, se um deles faltar ou mudar,
/// o link ainda sai com o endereço e o título.
enum LinkPasteboardReader {
    private static let bookmarkListType = NSPasteboard.PasteboardType("com.apple.Safari.bookmarkDictionaryList")
    private static let urlsWithTitlesType = NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")
    private static let urlNameType = NSPasteboard.PasteboardType("public.url-name")
    private static let linkMetadataType = NSPasteboard.PasteboardType("com.apple.linkpresentation.metadata")

    /// Os links da área de transferência, sem repetir página (mesma `WebLink.dedupeKey`), nesta ordem:
    /// favoritos e Lista de Leitura do Safari, endereços com títulos, itens com `public.url` (o título vem
    /// de `public.url-name` ou, sem ele, dos metadados do link) e, por último, o texto simples quando toda
    /// linha dele é um endereço. De duas leituras da mesma página fica o rascunho mais rico, na posição da
    /// primeira.
    static func drafts(from pasteboard: NSPasteboard) -> [LinkDraft] {
        var found = FoundLinks()
        let items = pasteboard.pasteboardItems ?? []

        for item in items {
            if let plist = propertyList(from: item.data(forType: bookmarkListType)) {
                found.add(SafariPasteboardPayload.drafts(fromBookmarkList: plist))
            }
        }
        if let plist = pasteboard.propertyList(forType: urlsWithTitlesType) {
            found.add(SafariPasteboardPayload.drafts(fromURLsWithTitles: plist))
        }
        for item in items {
            guard let text = item.string(forType: .URL), let url = WebLink.url(from: text) else { continue }
            found.add(LinkDraft(url: url, title: title(of: item)))
        }
        if let text = pasteboard.string(forType: .string) {
            for url in WebLink.urls(inText: text) {
                found.add(LinkDraft(url: url))
            }
        }
        return found.drafts
    }

    // MARK: Leitura

    /// O título de um item com endereço: `public.url-name` ou, sem ele, o do `LPLinkMetadata` arquivado.
    private static func title(of item: NSPasteboardItem) -> String? {
        if let name = nonBlank(item.string(forType: urlNameType)) { return name }
        guard let data = item.data(forType: linkMetadataType),
            let metadata = try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data)
        else { return nil }
        return nonBlank(metadata.title)
    }

    private static func propertyList(from data: Data?) -> Any? {
        guard let data else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: Sem repetidos

    /// Os rascunhos achados, na ordem da primeira ocorrência de cada página.
    private struct FoundLinks {
        private(set) var drafts: [LinkDraft] = []
        private var positions: [String: Int] = [:]

        mutating func add(_ newDrafts: [LinkDraft]) {
            for draft in newDrafts {
                add(draft)
            }
        }

        /// Página repetida só troca o rascunho se o novo trouxer mais; em empate vale o que veio primeiro.
        mutating func add(_ draft: LinkDraft) {
            let key = WebLink.dedupeKey(for: draft.url)
            guard let position = positions[key] else {
                positions[key] = drafts.count
                drafts.append(draft)
                return
            }
            if Self.richness(of: draft) > Self.richness(of: drafts[position]) { drafts[position] = draft }
        }

        /// Quantas informações o rascunho traz além do endereço: título, resumo e imagem.
        private static func richness(of draft: LinkDraft) -> Int {
            let texts = [draft.title, draft.summary].count { $0?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            return texts + (draft.imageURL == nil ? 0 : 1)
        }
    }
}
