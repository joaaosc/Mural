import Foundation

/// Imagem colada dentro de uma nota. O tamanho em pixels deixa a leitura reservar o espaço certo
/// antes de o arquivo ser decodificado.
public struct NoteAttachment: Codable, Hashable, Sendable {
    /// Nome do arquivo em `Items/`, no formato `<UUID>.<extensão>`.
    public var fileName: String
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(fileName: String, pixelWidth: Int, pixelHeight: Int) {
        self.fileName = fileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}
