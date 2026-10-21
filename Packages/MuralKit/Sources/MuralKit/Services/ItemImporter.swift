import Foundation

/// Copia conteúdo colado ou arrastado para a pasta de itens e cria o cartão correspondente.
///
/// A cópia é feita na hora porque o sandbox só libera o arquivo de origem
/// durante o paste/drop; depois disso o caminho original pode não abrir mais.
public struct ItemImporter: Sendable {
    public let itemsDirectory: URL
    private var fileManager: FileManager { .default }

    public init(itemsDirectory: URL) {
        self.itemsDirectory = itemsDirectory
    }

    /// URL do arquivo guardado para um cartão.
    public func fileURL(for item: BoardItem) -> URL? {
        guard let name = item.fileName else { return nil }
        return itemsDirectory.appendingPathComponent(name)
    }

    /// Importa um arquivo do disco: copia para a pasta de itens e devolve o cartão.
    public func importFile(at source: URL, parentID: UUID? = nil) throws -> BoardItem {
        guard fileManager.fileExists(atPath: source.path) else { throw ImportError.fileNotFound(source) }
        guard let kind = ContentClassifier.kind(forFileAt: source) else {
            throw ImportError.unsupportedType(source.pathExtension)
        }
        if kind == .text {
            let text = try Self.readText(at: source)
            var item = try importText(text, parentID: parentID)
            item.title = source.deletingPathExtension().lastPathComponent
            return item
        }
        let id = UUID()
        let fileName = "\(id.uuidString).\(source.pathExtension.lowercased())"
        try fileManager.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: itemsDirectory.appendingPathComponent(fileName))

        var item = BoardItem(
            id: id,
            kind: kind,
            title: source.deletingPathExtension().lastPathComponent,
            parentID: parentID,
            fileName: fileName
        )
        if kind == .image {
            item.imageMetadata = ImageInspector.inspect(itemsDirectory.appendingPathComponent(fileName))
        }
        return item
    }

    /// Guarda dados em memória (por exemplo, uma imagem copiada de outro app) como arquivo.
    public func importData(
        _ data: Data, fileExtension: String, kind: ItemKind, title: String, parentID: UUID? = nil
    ) throws -> BoardItem {
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension.lowercased())"
        try fileManager.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        let destination = itemsDirectory.appendingPathComponent(fileName)
        try data.write(to: destination, options: .atomic)
        var item = BoardItem(id: id, kind: kind, title: title, parentID: parentID, fileName: fileName)
        if kind == .image { item.imageMetadata = ImageInspector.inspect(destination) }
        return item
    }

    /// Transforma texto colado em post-it, lista ou nota, pelo classificador.
    public func importText(_ text: String, parentID: UUID? = nil) throws -> BoardItem {
        try importText(text, as: ContentClassifier.kind(forText: text), parentID: parentID)
    }

    /// Transforma texto no tipo escolhido: `.sticky`, `.checklist` ou `.text` (nota em
    /// Markdown). Na nota, um título `# Assim` na primeira linha vira o título do cartão
    /// e sai do corpo, para não aparecer duas vezes.
    public func importText(_ text: String, as kind: ItemKind, parentID: UUID? = nil) throws -> BoardItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyText }
        switch kind {
        case .checklist:
            let doc = ChecklistParser.parse(trimmed)
            return BoardItem(kind: .checklist, title: doc.title, parentID: parentID, checklist: doc)
        case .sticky:
            return BoardItem(
                kind: .sticky, title: ContentClassifier.title(forText: trimmed), parentID: parentID, text: trimmed,
                stickyColor: .yellow)
        default:
            if let (title, body) = Self.leadingHeading(of: trimmed) {
                return BoardItem(kind: .text, title: title, parentID: parentID, text: body.isEmpty ? nil : body)
            }
            return BoardItem(
                kind: .text, title: ContentClassifier.title(forText: trimmed), parentID: parentID, text: trimmed)
        }
    }

    /// Título `#` a `######` na primeira linha e o resto do texto, sem as linhas em branco do começo.
    static func leadingHeading(of text: String) -> (title: String, body: String)? {
        let lines = text.split(maxSplits: 1, omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let first = lines[0].trimmingCharacters(in: .whitespaces)
        let level = first.prefix { $0 == "#" }.count
        guard (1...6).contains(level), first.dropFirst(level).first?.isWhitespace == true else { return nil }
        var title = first.dropFirst(level).trimmingCharacters(in: .whitespaces)
        // Sequência de fechamento (`# Título ##`), como no Markdown.
        if let closing = title.range(of: #"\s+#+$"#, options: .regularExpression) { title.removeSubrange(closing) }
        guard !title.isEmpty else { return nil }
        let body = lines.count > 1 ? String(lines[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return (title, body)
    }

    /// Lê um arquivo de texto detectando a codificação pela marca de ordem de bytes;
    /// sem marca reconhecida, usa Latin-1, que aceita qualquer sequência de bytes.
    static func readText(at url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Apaga o arquivo guardado de um cartão, se houver. Erro de arquivo ausente é ignorado.
    public func removeFile(of item: BoardItem) {
        guard let url = fileURL(for: item) else { return }
        try? fileManager.removeItem(at: url)
    }
}
