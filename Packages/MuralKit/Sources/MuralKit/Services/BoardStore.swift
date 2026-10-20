import Foundation

public enum BoardStoreError: Error, Sendable {
    case corruptedFile(underlying: String)
}

/// Grava e lê o mural em `board.json` dentro de uma pasta.
public struct BoardStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("board.json") }
    /// Pasta onde os arquivos dos cartões são copiados.
    public var itemsDirectory: URL { directory.appendingPathComponent("Items", isDirectory: true) }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Pasta padrão do app: Application Support/Mural dentro do contêiner.
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Mural", isDirectory: true)
    }

    /// Lê o mural. Sem arquivo devolve `nil`; arquivo ilegível lança `corruptedFile`.
    public func load() throws -> Board? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Board.self, from: data)
        } catch {
            throw BoardStoreError.corruptedFile(underlying: String(describing: error))
        }
    }

    public func save(_ board: Board) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(board).write(to: fileURL, options: .atomic)
    }
}
