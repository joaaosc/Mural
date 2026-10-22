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
    /// Frases curtas escolhidas para o texto dobrável (corpo da nota ou abertura da lista).
    public var keySentences: KeySentenceRecord?
    /// Endereço e prévia da página, quando `kind == .link`.
    public var link: LinkInfo?
    /// Cor escolhida pela pessoa no menu do cartão, como as tags do Finder.
    public var colorTag: TagColor?
    /// Imagens coladas no corpo, quando `kind == .text`. Murais antigos não têm o campo.
    public var attachments: [NoteAttachment]?

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
        tag: String? = nil,
        keySentences: KeySentenceRecord? = nil,
        link: LinkInfo? = nil,
        colorTag: TagColor? = nil,
        attachments: [NoteAttachment]? = nil
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
        self.keySentences = keySentences
        self.link = link
        self.colorTag = colorTag
        self.attachments = attachments
    }
}

extension BoardItem {
    /// Texto que representa o cartão: o corpo, se houver, senão o título.
    public var displayText: String { text ?? title }

    /// Nota sem título nem corpo, ou post-it sem texto: um cartão novo que ficou vazio.
    public var isBlank: Bool {
        let body = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .text: return body.isEmpty && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sticky: return body.isEmpty
        default: return false
        }
    }

    /// Lista do cartão; uma lista sem conteúdo vira um documento vazio com o título.
    public var checklistDocument: ChecklistDocument {
        checklist ?? ChecklistDocument(title: title, sections: [])
    }
}

extension BoardItem {
    /// Arquivos que precisam existir em `Items/`: o do cartão e os dos anexos, sem repetição.
    public var requiredAssetFileNames: [String] {
        var names: [String] = []
        if let fileName { names.append(fileName) }
        names.append(contentsOf: (attachments ?? []).map(\.fileName))
        return Self.unique(names)
    }

    /// Todos os arquivos de `Items/` ligados ao cartão: os obrigatórios e, numa nota, os que o texto cita.
    public var assetFileNames: [String] {
        var names = requiredAssetFileNames
        if kind == .text, let text { names.append(contentsOf: NoteImageMarkup.referencedFileNames(in: text)) }
        return Self.unique(names)
    }

    private static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
