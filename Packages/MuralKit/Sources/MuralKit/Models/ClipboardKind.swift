import UniformTypeIdentifiers

/// O que a área de transferência guarda, para o painel mostrar o que o ⌘V faria antes de ler o conteúdo.
public enum ClipboardKind: Equatable, Sendable {
    case nothing
    /// Endereços da web; `count` é 0 enquanto ainda não foram lidos.
    case links(count: Int)
    case image
    case pdf
    /// Arquivos; `count` é 0 enquanto ainda não foram lidos.
    case files(count: Int)
    /// Texto colado; `nil` enquanto ainda não foi lido.
    case text(String?)
    /// Itens do app Música (faixa, álbum, playlist); `count` é 0 enquanto ainda não foram lidos.
    case music(count: Int)
    /// Contatos (vCard); `count` é 0 enquanto ainda não foram lidos.
    case contact(count: Int)

    /// O conteúdo já foi lido. É falso para o que só se sabe pelo tipo: links, arquivos, música e contatos sem contagem e texto
    /// sem o texto.
    public var isRead: Bool {
        switch self {
        case .links(let count), .files(let count), .music(let count), .contact(let count): count > 0
        case .text(let text): text != nil
        case .nothing, .image, .pdf: true
        }
    }

    /// Palpite pelos identificadores de tipo da área de transferência, sem ler o conteúdo.
    ///
    /// Segue a prioridade do ⌘V do mural: música (os tipos que o app Música põe ao copiar, lidos antes de tudo), contato (vCard, antes do texto e dos arquivos), depois
    /// a de `PasteboardImporter.read`: arquivos, PNG, PDF, outra imagem (TIFF, JPEG, HEIC, GIF), links, qualquer outro
    /// tipo de imagem e, por último, texto. Música, links, arquivos e texto saem sem contagem nem conteúdo (ver
    /// `isRead`). Links do Apple Music copiados sem os tipos do Música só viram música depois da leitura.
    /// - Parameter fileContentType: identificador do tipo do arquivo copiado (por exemplo `public.png`), quando quem
    ///   chama o conhece; um arquivo de imagem ou de PDF vale como imagem ou PDF, e qualquer outro como arquivos.
    public static func hint(typeIdentifiers: [String], fileContentType: String? = nil) -> ClipboardKind {
        let types = Set(typeIdentifiers)
        if !types.isDisjoint(with: musicTypes) { return .music(count: 0) }
        if types.contains(UTType.vCard.identifier) { return .contact(count: 0) }
        if types.contains(UTType.fileURL.identifier) {
            let fileType = fileContentType.flatMap { UTType($0) }
            if fileType?.conforms(to: .image) == true { return .image }
            if fileType?.conforms(to: .pdf) == true { return .pdf }
            return .files(count: 0)
        }
        if types.contains(UTType.png.identifier) { return .image }
        if types.contains(UTType.pdf.identifier) { return .pdf }
        if !types.isDisjoint(with: convertibleImageTypes) { return .image }
        if !types.isDisjoint(with: linkTypes) { return .links(count: 0) }
        // Como no ⌘V, uma imagem em formato incomum vale mais que o texto que vier junto.
        if typeIdentifiers.contains(where: { UTType($0)?.conforms(to: .image) == true }) { return .image }
        if !types.isDisjoint(with: textTypes) { return .text(nil) }
        return .nothing
    }

    /// Imagens que o ⌘V converte para PNG ao gravar.
    private static let convertibleImageTypes: Set<String> = [
        UTType.tiff.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.gif.identifier,
    ]

    /// Endereços da web, da área de transferência do sistema, do Safari (favoritos) e do WebKit antigo.
    private static let linkTypes: Set<String> = [
        UTType.url.identifier, "com.apple.Safari.bookmarkDictionaryList", "WebURLsWithTitlesPboardType",
    ]

    private static let textTypes: Set<String> = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

    /// O que o app Música põe na área de transferência ao copiar uma faixa, um álbum ou uma playlist.
    private static let musicTypes: Set<String> = [
        "com.apple.musicui.genericmusicitem", "com.apple.tv.metadata", "com.apple.music.playlist.name",
    ]
}
