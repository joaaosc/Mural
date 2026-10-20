import Foundation
import UniformTypeIdentifiers

/// Decide que tipo de cartão um arquivo ou texto deve virar.
public enum ContentClassifier {
    /// Tamanho máximo de texto que ainda vira post-it.
    public static let stickyLimit = 140

    /// Classifica um arquivo pelo tipo uniforme (UTType) e, como reserva, pela extensão.
    public static func kind(forFileAt url: URL) -> ItemKind? {
        if let type = UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .image) { return .image }
            if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
            if type.conforms(to: .pdf) { return .pdf }
            if type.conforms(to: .text) { return .text }
        }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff": return .image
        case "mov", "mp4", "m4v": return .video
        case "pdf": return .pdf
        case "txt", "md", "markdown", "rtf": return .text
        default: return nil
        }
    }

    /// Classifica texto colado: lista, post-it ou nota.
    public static func kind(forText text: String) -> ItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ChecklistDocument.looksLikeChecklist(trimmed) { return .checklist }
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
