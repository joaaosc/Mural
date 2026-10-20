import Foundation

/// Um cartão do mural. O mesmo tipo serve para pastas e para os cartões dentro delas.
public struct BoardItem: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var kind: ItemKind
    public var title: String
    public var createdAt: Date
    /// Pasta (coleção) a que o cartão pertence; `nil` quando está solto no mural.
    public var parentID: UUID?
    /// Posição no mural (usada só quando `parentID == nil`).
    public var position: BoardPoint
    /// Nome do arquivo dentro da pasta de itens, para tipos que guardam arquivo.
    public var fileName: String?
    /// Corpo de texto para notas e post-its; legenda para imagens.
    public var text: String?
    /// Conteúdo da lista, quando `kind == .checklist`.
    public var checklist: ChecklistDocument?
    public var stickyColor: StickyColor?
    /// Metadados lidos do arquivo de imagem.
    public var imageMetadata: ImageMetadata?
    /// Etiqueta curta exibida no canto da coleção (por exemplo, "CLIENT 001").
    public var tag: String?

    public init(
        id: UUID = UUID(),
        kind: ItemKind,
        title: String,
        createdAt: Date = .now,
        parentID: UUID? = nil,
        position: BoardPoint = .zero,
        fileName: String? = nil,
        text: String? = nil,
        checklist: ChecklistDocument? = nil,
        stickyColor: StickyColor? = nil,
        imageMetadata: ImageMetadata? = nil,
        tag: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.parentID = parentID
        self.position = position
        self.fileName = fileName
        self.text = text
        self.checklist = checklist
        self.stickyColor = stickyColor
        self.imageMetadata = imageMetadata
        self.tag = tag
    }
}
