import Foundation
import StretchText

/// Regras do Markdown das imagens coladas numa nota: a linha `![alt](arquivo)`, os nomes que a nota
/// cita e o marcador provisório que o editor troca quando o arquivo fica pronto.
public enum NoteImageMarkup {
    public static let defaultAlt = "Imagem colada"

    private static let pendingScheme = "mural-colando:"
    private static let pendingAlt = "Colando imagem…"
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "gif", "tif", "tiff", "webp", "bmp",
    ]

    /// Linha de imagem Markdown para um arquivo de `Items/`.
    public static func line(fileName: String, alt: String = defaultAlt) -> String {
        "![\(alt)](\(fileName))"
    }

    /// Texto a inserir entre `preceding` e `following`: cada imagem num bloco próprio, separada do
    /// texto vizinho e das outras por uma linha em branco, sem linhas em branco sobrando nas pontas.
    public static func insertion(of lines: [String], after preceding: Substring, before following: Substring) -> String {
        guard !lines.isEmpty else { return "" }
        let before = isBlank(preceding) ? "" : String(repeating: "\n", count: max(0, 2 - trailingNewlines(in: preceding)))
        let after = isBlank(following) ? "" : String(repeating: "\n", count: max(0, 2 - leadingNewlines(in: following)))
        return before + lines.joined(separator: "\n\n") + after
    }

    /// Nomes de arquivo citados em linhas de imagem (as dentro de cerca de código não contam), só os
    /// que são de anexo, sem repetição e na ordem em que aparecem.
    public static func referencedFileNames(in text: String) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for segment in TextSegmenter.segment(text).segments where segment.kind == .image {
            guard let image = MarkdownImage.parse(segment.text), isAttachmentName(image.source),
                seen.insert(image.source).inserted
            else { continue }
            names.append(image.source)
        }
        return names
    }

    /// Verdadeiro para exatamente `<UUID>.<extensão de imagem>`, o nome que o `ItemImporter` gera.
    public static func isAttachmentName(_ name: String) -> Bool {
        guard !name.contains("/"), !name.contains("..") else { return false }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 36, UUID(uuidString: String(parts[0])) != nil else { return false }
        return imageExtensions.contains(parts[1].lowercased())
    }

    // MARK: Marcador provisório

    /// Linha que ocupa o lugar da imagem enquanto o arquivo é gravado.
    public static func pendingLine(token: UUID) -> String {
        "![\(pendingAlt)](\(pendingScheme)\(token.uuidString))"
    }

    /// Verdadeiro para a linha de um marcador provisório (de qualquer token).
    public static func isPendingLine(_ line: some StringProtocol) -> Bool {
        MarkdownImage.parse(line)?.source.hasPrefix(pendingScheme) == true
    }

    /// Troca a linha do marcador por `replacement`; vazio tira a linha sem deixar duas linhas em branco seguidas.
    /// - Returns: `nil` se o marcador não está no texto.
    public static func replacingPending(_ token: UUID, with replacement: String, in text: String) -> String? {
        let marker = pendingLine(token: token)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == marker }) else {
            guard text.contains(marker) else { return nil }
            return text.replacingOccurrences(of: marker, with: replacement)
        }
        if !replacement.isEmpty {
            lines[index] = replacement
            return lines.joined(separator: "\n")
        }
        lines.remove(at: index)
        if index == 0 {
            while lines.first.map(isBlank) == true { lines.removeFirst() }
        } else if index >= lines.count {
            while lines.last.map(isBlank) == true { lines.removeLast() }
        } else if isBlank(lines[index - 1]), isBlank(lines[index]) {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Interno

    private static func isBlank(_ text: some StringProtocol) -> Bool {
        text.allSatisfy(\.isWhitespace)
    }

    private static func trailingNewlines(in text: Substring) -> Int {
        text.reversed().prefix { $0.isNewline || $0 == " " || $0 == "\t" }.filter(\.isNewline).count
    }

    private static func leadingNewlines(in text: Substring) -> Int {
        text.prefix { $0.isNewline || $0 == " " || $0 == "\t" }.filter(\.isNewline).count
    }
}
