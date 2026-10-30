import Foundation
import StretchText
import UniformTypeIdentifiers

/// Decide que tipo de cartão um arquivo ou texto deve virar.
public enum ContentClassifier {
    /// Tamanho máximo de texto que ainda vira post-it.
    public static let stickyLimit = 140

    /// Classifica um arquivo pelo tipo uniforme (UTType) da extensão.
    public static func kind(forFileAt url: URL) -> ItemKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        return kind(for: type)
    }

    /// Classifies a file using an explicit uniform type. This is the preferred
    /// path for providers such as PhotosPicker, whose temporary file name is
    /// not a reliable source of content type information.
    public static func kind(for type: UTType) -> ItemKind? {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .plainText) { return .text }
        return nil
    }

    /// Returns a safe extension for a supported type. The provider's original
    /// filename is used only as a fallback when the type has no preferred one.
    public static func preferredFileExtension(for type: UTType) -> String? {
        guard kind(for: type) != nil else { return nil }
        return type.preferredFilenameExtension
    }

    /// Classifica texto colado: lista, post-it ou nota. Uma lista numerada (`1. `, `2) `) ou com `+ `, `◦ ` e `▪ ` também
    /// vale como lista (`ChecklistParser.looksLikeChecklist`), no ⌘V como no painel.
    public static func kind(forText text: String) -> ItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ChecklistParser.looksLikeChecklist(trimmed) { return .checklist }
        if trimmed.count <= stickyLimit { return .sticky }
        return .text
    }

    /// Opções do popup de colar: a sugestão é a mesma classificação de `kind(forText:)`.
    public static func pasteChoice(forText text: String) -> PasteChoice {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return PasteChoice(suggested: kind(forText: trimmed), offersChecklist: ChecklistParser.looksLikeChecklist(trimmed))
    }

    /// Título sugerido para um texto: a primeira linha, encurtada.
    public static func title(forText text: String, limit: Int = 48) -> String {
        // Linhas de imagem (e o marcador provisório) não servem de título.
        let first =
            text.split(whereSeparator: \.isNewline)
            .first { MarkdownImage.parse($0) == nil && !NoteImageMarkup.isPendingLine($0) }
            .map(String.init) ?? "Nota"
        let clean = first.trimmingCharacters(in: CharacterSet(charactersIn: "#-*• ").union(.whitespaces))
        if clean.count <= limit { return clean.isEmpty ? "Nota" : clean }
        return String(clean.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
