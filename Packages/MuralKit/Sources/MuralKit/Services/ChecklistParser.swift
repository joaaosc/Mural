import Foundation

/// Lê uma lista escrita em texto simples.
///
/// Regras, linha a linha (linhas vazias são ignoradas):
/// 1. Linha com marcador (`- `, `* `, `• `, `- [ ] `, `- [x] `…) vira item; `[x]` entra marcado.
/// 2. A primeira linha sem marcador vira o título (sem `#` no começo).
/// 3. Antes da primeira seção, uma linha com cara de parágrafo (termina em ponto ou passa de
///    40 caracteres) vai para o texto de abertura.
/// 4. Qualquer outra linha sem marcador abre uma seção nova com esse título.
/// Itens que aparecem antes de qualquer seção ficam numa seção sem título.
public enum ChecklistParser {
    static let bulletPrefixes = ["- [ ] ", "- [x] ", "- [X] ", "- ", "* ", "• ", "[ ] ", "[x] "]
    static let paragraphLength = 40

    /// Diz se o texto parece uma lista: pelo menos duas linhas com marcador.
    public static func looksLikeChecklist(_ text: String) -> Bool {
        lines(of: text).filter { entry(from: $0) != nil }.count >= 2
    }

    public static func parse(_ text: String) -> ChecklistDocument {
        var title: String?
        var intro: [String] = []
        var sections: [ChecklistSection] = []

        for line in lines(of: text) {
            if let entry = entry(from: line) {
                if sections.isEmpty {
                    sections.append(ChecklistSection(title: "", entries: []))
                }
                sections[sections.count - 1].entries.append(entry)
            } else if title == nil {
                title = line.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            } else if sections.isEmpty && isParagraph(line) {
                intro.append(line)
            } else {
                sections.append(ChecklistSection(title: line, entries: []))
            }
        }

        let resolvedTitle = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Lista"
        return ChecklistDocument(title: resolvedTitle, intro: intro.joined(separator: " "), sections: sections)
    }

    /// Escreve a lista em texto simples, no formato que `parse` lê de volta
    /// (o texto de abertura volta como abertura se terminar em ponto ou for longo).
    public static func format(_ document: ChecklistDocument) -> String {
        var lines = [document.title]
        if !document.intro.isEmpty { lines.append(document.intro) }
        for section in document.sections {
            if !section.title.isEmpty { lines.append(section.title) }
            lines += section.entries.map { "- [\($0.isDone ? "x" : " ")] \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }

    private static func lines(of text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func entry(from line: String) -> ChecklistEntry? {
        guard let prefix = bulletPrefixes.first(where: { line.hasPrefix($0) }) else { return nil }
        let isDone = prefix.lowercased().contains("[x]")
        return ChecklistEntry(text: String(line.dropFirst(prefix.count)), isDone: isDone)
    }

    private static func isParagraph(_ line: String) -> Bool {
        line.hasSuffix(".") || line.count > paragraphLength
    }
}
