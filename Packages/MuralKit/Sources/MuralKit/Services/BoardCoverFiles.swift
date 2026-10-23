import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Guarda a capa de cada mural (uma miniatura em JPEG) numa pasta própria, ao lado dos murais.
///
/// A pasta fica fora dos pacotes: a gravação de um pacote o refaz por staging e a exportação valida o que há
/// nele, então uma capa lá dentro se perderia ou seria recusada. O arquivo se chama `<UUID do mural>-r<revisão>.jpg`
/// e a revisão no nome diz se a capa ainda vale para o mural salvo: se a revisão do mural for outra, a capa está velha.
/// Cada mural tem uma capa só: gravar uma nova apaga as anteriores.
public struct BoardCoverFiles: Sendable {
    /// Uma capa gravada: de que mural, de qual revisão do conteúdo e onde está o arquivo.
    public struct Cover: Equatable, Sendable {
        public let boardID: BoardID
        public let revision: Int
        public let url: URL

        public init(boardID: BoardID, revision: Int, url: URL) {
            self.boardID = boardID
            self.revision = revision
            self.url = url
        }
    }

    private static let fileExtension = "jpg"

    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// A capa com a maior revisão do mural; arquivos com nome fora do padrão são ignorados.
    public func latest(for boardID: BoardID) -> Cover? {
        covers().filter { $0.boardID == boardID }.max { $0.revision < $1.revision }
    }

    /// Codifica a imagem em JPEG, grava de forma atômica (criando a pasta) e só depois apaga as outras revisões
    /// do mesmo mural, então uma queda no meio deixa duas capas, nunca nenhuma. Chamadas ao mesmo tempo para o
    /// mesmo mural devem ser serializadas por quem chama.
    /// - Parameter quality: de 0 a 1; valores fora disso são limitados.
    /// - Throws: `BoardCoverFilesError.invalidRevision` se a revisão for negativa, `.encodingFailed` se a imagem
    ///   não puder virar JPEG (a pasta nem é criada) e erro de disco ao criar a pasta ou gravar.
    @discardableResult
    public func store(_ image: CGImage, for boardID: BoardID, revision: Int, quality: Double = 0.85) throws -> Cover {
        guard revision >= 0 else { throw BoardCoverFilesError.invalidRevision }
        let data = try Self.jpegData(of: image, quality: quality)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.fileName(for: boardID, revision: revision)
        let url = fileURL(named: name)
        try data.write(to: url, options: .atomic)

        for other in covers() where other.boardID == boardID && other.url.lastPathComponent != name {
            try? FileManager.default.removeItem(at: other.url)
        }
        return Cover(boardID: boardID, revision: revision, url: url)
    }

    /// Apaga todas as capas do mural; uma pasta que não existe não é erro.
    public func remove(for boardID: BoardID) {
        for cover in covers() where cover.boardID == boardID {
            try? FileManager.default.removeItem(at: cover.url)
        }
    }

    /// Apaga as capas de murais que não estão em `boardIDs`. Arquivos fora do padrão, subpastas e arquivos ocultos
    /// não são tocados, e uma pasta que não existe não é erro.
    /// - Returns: os nomes apagados, em ordem alfabética.
    @discardableResult
    public func sweep(keeping boardIDs: Set<BoardID>) -> [String] {
        var removed: [String] = []
        for cover in covers() where !boardIDs.contains(cover.boardID) {
            guard (try? FileManager.default.removeItem(at: cover.url)) != nil else { continue }
            removed.append(cover.url.lastPathComponent)
        }
        return removed.sorted()
    }

    // MARK: Nomes

    /// `<UUID em maiúsculas>-r<revisão>.jpg`.
    static func fileName(for boardID: BoardID, revision: Int) -> String {
        "\(boardID.rawValue.uuidString)-r\(revision).\(fileExtension)"
    }

    /// O mural e a revisão de um nome de capa; `nil` para qualquer nome que `fileName(for:revision:)` não geraria:
    /// UUID inválido ou em minúsculas, revisão negativa, com sinal, com zeros à esquerda ou não numérica, outra
    /// extensão e nome oculto.
    static func parse(_ fileName: String) -> (boardID: BoardID, revision: Int)? {
        guard fileName.hasSuffix(".\(fileExtension)"), let separator = fileName.range(of: "-r") else { return nil }
        let idText = fileName[..<separator.lowerBound]
        let revisionText = fileName[separator.upperBound...].dropLast(fileExtension.count + 1)
        guard let uuid = UUID(uuidString: String(idText)), let revision = Int(revisionText), revision >= 0 else { return nil }
        let boardID = BoardID(rawValue: uuid)
        // Só vale o nome exato que seria gerado: dá uma única forma para cada par mural e revisão.
        return Self.fileName(for: boardID, revision: revision) == fileName ? (boardID, revision) : nil
    }

    private func fileURL(named name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    /// As capas que há na pasta: arquivos comuns, não ocultos, com nome no padrão. Pasta ausente ou ilegível dá lista vazia.
    private func covers() -> [Cover] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        else { return [] }

        return urls.compactMap { url in
            let name = url.lastPathComponent
            guard let parsed = Self.parse(name), (try? url.resourceValues(forKeys: keys))?.isRegularFile == true else { return nil }
            // O endereço sai do nome, como em `store`, para a mesma capa ser igual venha de onde vier.
            return Cover(boardID: parsed.boardID, revision: parsed.revision, url: fileURL(named: name))
        }
    }

    // MARK: Imagem

    private static func jpegData(of image: CGImage, quality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw BoardCoverFilesError.encodingFailed
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1)]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BoardCoverFilesError.encodingFailed }
        return output as Data
    }
}

public enum BoardCoverFilesError: Error, Equatable {
    /// A revisão da capa não pode ser negativa.
    case invalidRevision
    /// A imagem não pôde ser codificada em JPEG.
    case encodingFailed
}
