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
    /// Corpo de texto para notas e post-its. Legendas ficam em `caption`.
    public var text: String?
    /// Legenda persistente separada do corpo. Em murais antigos, o texto de uma
    /// imagem é migrado para este campo ao decodificar.
    public var caption: String?
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
    /// Último estado conhecido do lembrete, quando `kind == .reminder`. Murais antigos não têm o campo.
    public var reminder: ReminderSnapshot?
    /// Último estado conhecido do item do Apple Music, quando `kind == .music`. Murais antigos não têm o campo.
    public var music: MusicSnapshot?
    /// Cor escolhida pela pessoa no menu do cartão, como as tags do Finder.
    public var colorTag: TagColor?
    /// Imagens coladas no corpo, quando `kind == .text`. Murais antigos não têm o campo.
    public var attachments: [NoteAttachment]?
    /// Lugar livre do post-it dentro da pasta, depois que a pessoa o arrastou lá: canto superior esquerdo, com `x` a partir
    /// do meio da pasta e `y` a partir do topo. `nil` deixa o cartão nas colunas da pasta. Murais antigos não têm o campo.
    public var folderPosition: BoardPoint?
    /// Tamanho que a pessoa escolheu para o cartão solto no mural; `nil` usa o padrão do tipo (`BoardLayout.cardSize(for:)`).
    /// Por ora só post-its mudam de tamanho (`BoardLayout.isResizable`). Dentro de uma pasta o campo é ignorado, porque a pasta
    /// usa o próprio layout, mas continua guardado para quando o post-it voltar ao mural. Murais antigos não têm o campo.
    public var size: BoardSize?

    public init(
        id: UUID = UUID(),
        kind: ItemKind,
        title: String,
        createdAt: Date = .now,
        parentID: UUID? = nil,
        position: BoardPoint = .zero,
        fileName: String? = nil,
        text: String? = nil,
        caption: String? = nil,
        checklist: ChecklistDocument? = nil,
        stickyColor: StickyColor? = nil,
        imageMetadata: ImageMetadata? = nil,
        tag: String? = nil,
        keySentences: KeySentenceRecord? = nil,
        link: LinkInfo? = nil,
        reminder: ReminderSnapshot? = nil,
        music: MusicSnapshot? = nil,
        colorTag: TagColor? = nil,
        attachments: [NoteAttachment]? = nil,
        folderPosition: BoardPoint? = nil,
        size: BoardSize? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.createdAt = createdAt
        self.parentID = parentID
        self.position = position
        self.fileName = fileName
        self.text = text
        self.caption = caption
        self.checklist = checklist
        self.stickyColor = stickyColor
        self.imageMetadata = imageMetadata
        self.tag = tag
        self.keySentences = keySentences
        self.link = link
        self.reminder = reminder
        self.music = music
        self.colorTag = colorTag
        self.attachments = attachments
        self.folderPosition = folderPosition
        self.size = size
    }
}

extension BoardItem {
    private enum CodingKeys: String, CodingKey {
        case id, kind, title, createdAt, parentID, position, fileName, text, caption
        case checklist, stickyColor, imageMetadata, tag, keySentences, link, reminder, music
        case colorTag, attachments, folderPosition, size
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(ItemKind.self, forKey: .kind)
        let legacyText = try container.decodeIfPresent(String.self, forKey: .text)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            kind: kind,
            title: try container.decode(String.self, forKey: .title),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            parentID: try container.decodeIfPresent(UUID.self, forKey: .parentID),
            position: try container.decodeIfPresent(BoardPoint.self, forKey: .position) ?? .zero,
            fileName: try container.decodeIfPresent(String.self, forKey: .fileName),
            text: kind == .image ? nil : legacyText,
            caption: try container.decodeIfPresent(String.self, forKey: .caption)
                ?? (kind == .image ? legacyText : nil),
            checklist: try container.decodeIfPresent(ChecklistDocument.self, forKey: .checklist),
            stickyColor: try container.decodeIfPresent(StickyColor.self, forKey: .stickyColor),
            imageMetadata: try container.decodeIfPresent(ImageMetadata.self, forKey: .imageMetadata),
            tag: try container.decodeIfPresent(String.self, forKey: .tag),
            keySentences: try container.decodeIfPresent(KeySentenceRecord.self, forKey: .keySentences),
            link: try container.decodeIfPresent(LinkInfo.self, forKey: .link),
            reminder: try container.decodeIfPresent(ReminderSnapshot.self, forKey: .reminder),
            music: try container.decodeIfPresent(MusicSnapshot.self, forKey: .music),
            colorTag: try container.decodeIfPresent(TagColor.self, forKey: .colorTag),
            attachments: try container.decodeIfPresent([NoteAttachment].self, forKey: .attachments),
            folderPosition: try container.decodeIfPresent(BoardPoint.self, forKey: .folderPosition),
            size: try container.decodeIfPresent(BoardSize.self, forKey: .size))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(parentID, forKey: .parentID)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(fileName, forKey: .fileName)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(caption, forKey: .caption)
        try container.encodeIfPresent(checklist, forKey: .checklist)
        try container.encodeIfPresent(stickyColor, forKey: .stickyColor)
        try container.encodeIfPresent(imageMetadata, forKey: .imageMetadata)
        try container.encodeIfPresent(tag, forKey: .tag)
        try container.encodeIfPresent(keySentences, forKey: .keySentences)
        try container.encodeIfPresent(link, forKey: .link)
        try container.encodeIfPresent(reminder, forKey: .reminder)
        try container.encodeIfPresent(music, forKey: .music)
        try container.encodeIfPresent(colorTag, forKey: .colorTag)
        try container.encodeIfPresent(attachments, forKey: .attachments)
        try container.encodeIfPresent(folderPosition, forKey: .folderPosition)
        try container.encodeIfPresent(size, forKey: .size)
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

    /// Post-it solto num lugar livre da pasta onde está: fica fora das colunas, por cima dos outros cartões.
    public var isPlacedInFolder: Bool { kind == .sticky && parentID != nil && folderPosition != nil }

    /// Lista do cartão; uma lista sem conteúdo vira um documento vazio com o título.
    public var checklistDocument: ChecklistDocument {
        checklist ?? ChecklistDocument(title: title, sections: [])
    }
}

extension BoardItem {
    /// Arquivos que precisam existir em `Items/`: o do cartão e os dos anexos, sem repetição.
    public var requiredAssetFileNames: [String] {
        assetFileNames(includeTextReferences: false)
    }

    /// Todos os arquivos de `Items/` ligados ao cartão: os obrigatórios e, numa nota, os que o texto cita.
    public var assetFileNames: [String] {
        assetFileNames(includeTextReferences: true)
    }

    private func assetFileNames(includeTextReferences: Bool) -> [String] {
        let attachmentCount = attachments?.count ?? 0
        var names: [String] = []
        names.reserveCapacity((fileName == nil ? 0 : 1) + attachmentCount)
        var seen = Set<String>()
        seen.reserveCapacity(names.capacity)

        if let fileName, seen.insert(fileName).inserted {
            names.append(fileName)
        }
        for attachment in attachments ?? [] where seen.insert(attachment.fileName).inserted {
            names.append(attachment.fileName)
        }
        if includeTextReferences, kind == .text, let text {
            for name in NoteImageMarkup.referencedFileNames(in: text) where seen.insert(name).inserted {
                names.append(name)
            }
        }
        return names
    }
}
