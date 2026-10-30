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
    /// que são de anexo, sem repetição e na ordem em que aparecem. Cartões embutidos não entram: não têm arquivo.
    public static func referencedFileNames(in text: String) -> [String] {
        references(in: text).fileNames
    }

    /// Os nomes de arquivo de imagem e os ids de cartões embutidos citados no texto, numa só passada de segmentação. Cada lista
    /// vem sem repetição e na ordem em que aparece; linhas dentro de cerca de código não contam.
    public static func references(in text: String) -> (fileNames: [String], cardIDs: [UUID]) {
        var seenNames = Set<String>()
        var seenIDs = Set<UUID>()
        var names: [String] = []
        var ids: [UUID] = []
        for segment in TextSegmenter.segment(text).segments where segment.kind == .image {
            guard let image = MarkdownImage.parse(segment.text) else { continue }
            if isAttachmentName(image.source) {
                if seenNames.insert(image.source).inserted { names.append(image.source) }
            } else if let id = cardID(inSource: image.source), seenIDs.insert(id).inserted {
                ids.append(id)
            }
        }
        return (names, ids)
    }

    /// Verdadeiro para exatamente `<UUID>.<extensão de imagem>`, o nome que o `ItemImporter` gera.
    public static func isAttachmentName(_ name: String) -> Bool {
        guard !name.contains("/"), !name.contains("..") else { return false }
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 36, UUID(uuidString: String(parts[0])) != nil else { return false }
        return imageExtensions.contains(parts[1].lowercased())
    }

    // MARK: Cartões embutidos

    /// Início da origem de uma linha de cartão embutido: `![título](mural-card:<UUID>)`.
    public static let cardScheme = "mural-card:"

    private static let cardExtension = "card"
    private static let cardFallbackTitle = "Cartão"

    /// Linha de imagem Markdown para um cartão embutido. O título perde `]` e quebras de linha, que fechariam o texto alternativo
    /// ou partiriam a linha; sem nada sobrando, vira "Cartão".
    public static func cardLine(id: UUID, title: String) -> String {
        let cleaned =
            title
            .replacingOccurrences(of: "]", with: "")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return "![\(cleaned.isEmpty ? cardFallbackTitle : cleaned)](\(cardScheme)\(id.uuidString))"
    }

    /// Verdadeiro para a origem de um cartão embutido (`mural-card:…`), já lida da linha de imagem.
    public static func isCardSource(_ source: String) -> Bool {
        source.hasPrefix(cardScheme)
    }

    /// O id de uma origem `mural-card:<UUID>`; `nil` se a origem é de outro tipo ou o id é inválido.
    public static func cardID(inSource source: String) -> UUID? {
        guard isCardSource(source) else { return nil }
        return UUID(uuidString: String(source.dropFirst(cardScheme.count)))
    }

    /// Ids de cartões citados em linhas de imagem (as dentro de cerca de código não contam), sem repetição e na ordem em que
    /// aparecem.
    public static func referencedCardIDs(in text: String) -> [UUID] {
        references(in: text).cardIDs
    }

    /// O nome do anexo de um cartão embutido: `<UUID>.card`.
    public static func cardAttachmentName(for id: UUID) -> String {
        "\(id.uuidString).\(cardExtension)"
    }

    /// Verdadeiro para exatamente `<UUID>.card`.
    public static func isCardAttachmentName(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 2 && parts[0].count == 36 && UUID(uuidString: String(parts[0])) != nil && parts[1] == cardExtension
    }

    // MARK: Marcador provisório

    /// Linha que ocupa o lugar da imagem enquanto o arquivo é gravado.
    public static func pendingLine(token: UUID) -> String {
        "![\(pendingAlt)](\(pendingScheme)\(token.uuidString))"
    }

    /// Verdadeiro para a linha de um marcador provisório (de qualquer token).
    public static func isPendingLine(_ line: some StringProtocol) -> Bool {
        MarkdownImage.parse(line).map { isPendingSource($0.source) } == true
    }

    /// Verdadeiro para a origem de um marcador provisório (`mural-colando:…`), já lida da linha de imagem.
    public static func isPendingSource(_ source: String) -> Bool {
        source.hasPrefix(pendingScheme)
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
