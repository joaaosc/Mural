import Foundation
import UniformTypeIdentifiers

/// Decide que tipo de cartão um arquivo ou texto deve virar.
public enum ContentClassifier {
    /// Tamanho máximo de texto que ainda vira post-it.
    public static let stickyLimit = 140

    /// Classifica um arquivo pelo tipo uniforme (UTType) da extensão.
    public static func kind(forFileAt url: URL) -> ItemKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .plainText) { return .text }
        return nil
    }

    /// Classifica texto colado: lista, post-it ou nota.
    public static func kind(forText text: String) -> ItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ChecklistParser.looksLikeChecklist(trimmed) { return .checklist }
        if trimmed.count <= stickyLimit { return .sticky }
        return .text
    }

    /// Título sugerido para um texto: a primeira linha, encurtada.
    public static func title(forText text: String, limit: Int = 48) -> String {
        let first = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Nota"
        let clean = first.trimmingCharacters(in: CharacterSet(charactersIn: "#-*• ").union(.whitespaces))
        if clean.count <= limit { return clean.isEmpty ? "Nota" : clean }
        return String(clean.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
