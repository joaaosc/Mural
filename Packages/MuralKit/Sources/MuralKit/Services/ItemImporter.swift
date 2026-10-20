import Foundation

public enum ImportError: Error, Equatable, Sendable {
    case fileNotFound(URL)
    case unsupportedType(String)
    case emptyText
}

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
    public func importFile(at source: URL, parentID: UUID? = nil, position: BoardPoint = .zero) throws -> BoardItem {
        guard fileManager.fileExists(atPath: source.path) else { throw ImportError.fileNotFound(source) }
        guard let kind = ContentClassifier.kind(forFileAt: source) else {
            throw ImportError.unsupportedType(source.pathExtension)
        }
        if kind == .text {
            let text = try Self.readText(at: source)
            var item = try importText(text, parentID: parentID, position: position)
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
            position: position,
            fileName: fileName
        )
        if kind == .image {
            item.imageMetadata = ImageInspector.inspect(itemsDirectory.appendingPathComponent(fileName))
        }
        return item
    }

    /// Guarda dados em memória (por exemplo, uma imagem copiada de outro app) como arquivo.
    public func importData(
        _ data: Data, fileExtension: String, kind: ItemKind, title: String, parentID: UUID? = nil, position: BoardPoint = .zero
    ) throws -> BoardItem {
        let id = UUID()
        let fileName = "\(id.uuidString).\(fileExtension.lowercased())"
        try fileManager.createDirectory(at: itemsDirectory, withIntermediateDirectories: true)
        let destination = itemsDirectory.appendingPathComponent(fileName)
        try data.write(to: destination, options: .atomic)
        var item = BoardItem(id: id, kind: kind, title: title, parentID: parentID, position: position, fileName: fileName)
        if kind == .image { item.imageMetadata = ImageInspector.inspect(destination) }
        return item
    }

    /// Transforma texto colado em post-it, lista ou nota.
    public func importText(_ text: String, parentID: UUID? = nil, position: BoardPoint = .zero) throws -> BoardItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyText }
        let kind = ContentClassifier.kind(forText: trimmed)
        switch kind {
        case .checklist:
            let doc = ChecklistDocument.parse(trimmed)
            return BoardItem(kind: .checklist, title: doc.title, parentID: parentID, position: position, checklist: doc)
        case .sticky:
            return BoardItem(
                kind: .sticky, title: ContentClassifier.title(forText: trimmed), parentID: parentID, position: position, text: trimmed,
                stickyColor: .yellow)
        default:
            return BoardItem(
                kind: .text, title: ContentClassifier.title(forText: trimmed), parentID: parentID, position: position, text: trimmed)
        }
    }

    /// Lê um arquivo de texto detectando a codificação pela marca de ordem de bytes;
    /// sem marca, tenta UTF-8 e depois Latin-1 (que nunca falha).
    static func readText(at url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let text = try? String(contentsOf: url, usedEncoding: &encoding) { return text }
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    /// Apaga o arquivo guardado de um cartão, se houver. Erro de arquivo ausente é ignorado.
    public func removeFile(of item: BoardItem) {
        guard let url = fileURL(for: item) else { return }
        try? fileManager.removeItem(at: url)
    }
}
