import Foundation

/// O que de um cartão vai para as outras pessoas e o que é de cada Mac.
///
/// As frases curtas são escolhidas por cada Mac, com o modelo do aparelho, então ficam locais. A prévia de um link e a capa de uma
/// música são arquivos guardados fora de `Items/`, com o nome que cada Mac deu: se subissem, os Macs se sobrescreveriam. Por isso
/// link e música são compartilhados, mas cada um tem partes locais, declaradas aqui pelas chaves do JSON.
public enum SharedFieldPolicy {
    /// Se o campo viaja para as outras pessoas (`shared`) ou fica no Mac (`local`).
    public enum Scope: Sendable {
        case shared
        case local
    }

    /// O escopo de cada campo do cartão. O `switch` é exaustivo: um campo novo só compila depois de ganhar um escopo.
    public static func scope(of field: BoardItem.Field) -> Scope {
        switch field {
        case .keySentences:
            .local
        case .kind, .title, .createdAt, .parentID, .position, .fileName, .text, .caption, .checklist, .stickyColor, .imageMetadata,
            .tag, .link, .reminder, .music, .contact, .colorTag, .attachments, .folderPosition, .size:
            .shared
        }
    }

    // MARK: Partes locais de link e música

    /// Chaves do JSON de `LinkInfo` que são de cada Mac: os arquivos da prévia e o estado da busca (`preview`).
    public static let localLinkKeys: Set<String> = ["previewImageFile", "iconFile", "preview"]

    /// Chaves do JSON de `LinkInfo` que vão para as outras pessoas: o endereço e o que a página declara.
    public static let sharedLinkKeys: Set<String> = ["url", "pageTitle", "siteName", "summary", "remoteImageURL"]

    /// Chaves do JSON de `MusicSnapshot` que são de cada Mac: o arquivo da capa e o id da playlist na biblioteca daquele Mac.
    public static let localMusicKeys: Set<String> = ["artworkFile", "libraryID"]

    /// Chaves do JSON de `MusicSnapshot` que vão para as outras pessoas.
    public static let sharedMusicKeys: Set<String> = [
        "kind", "catalogID", "storefront", "libraryPlaylistName", "url", "title", "subtitle", "albumTitle", "artworkTemplate",
        "backgroundHex", "primaryTextHex", "secondaryTextHex", "trackCount", "releaseDate", "duration",
    ]

    /// Chaves do JSON de `ContactSnapshot` que são de cada Mac: o arquivo da foto reduzida.
    public static let localContactKeys: Set<String> = ["thumbnailFile"]

    /// Chaves do JSON de `ContactSnapshot` que vão para as outras pessoas.
    public static let sharedContactKeys: Set<String> = ["givenName", "familyName", "organization", "phones", "emails"]

    /// Tipos que só o Mac de quem criou o cartão atualiza a partir do Lembretes ou do Música; os outros mostram o último estado
    /// guardado.
    public static let creatorMaintainedKinds: Set<ItemKind> = [.reminder, .music]

    // MARK: Cópias

    /// A prévia e a capa de um link ou de uma música embutidos numa nota (`NoteAttachment.card`) são locais como as dos cartões
    /// avulsos: saem de `shared(_:)` e voltam em `preservingLocalFields(of:in:)`, casando os anexos pelo nome (`<UUID>.card`).
    /// O lembrete embutido não tem parte local.
    static func sharedCard(_ card: EmbeddedCard) -> EmbeddedCard {
        switch card {
        case .link(var link):
            link.previewImageFile = nil
            link.iconFile = nil
            link.preview = .pending
            return .link(link)
        case .music(var music):
            music.artworkFile = nil
            music.libraryID = nil
            return .music(music)
        case .contact(var contact):
            contact.thumbnailFile = nil
            return .contact(contact)
        case .reminder:
            return card
        }
    }

    /// O cartão embutido que chegou, com as partes locais do que este Mac já tinha quando os dois são o mesmo link ou a mesma
    /// música (mesmos critérios dos cartões avulsos).
    private static func preservingLocalFields(ofCard local: EmbeddedCard, in incoming: EmbeddedCard) -> EmbeddedCard {
        switch (local, incoming) {
        case (.link(let localLink), .link(var link)) where localLink.url == link.url:
            link.previewImageFile = localLink.previewImageFile
            link.iconFile = localLink.iconFile
            link.preview = localLink.preview
            return .link(link)
        case (.contact(let localContact), .contact(var contact)) where localContact.dedupeKey == contact.dedupeKey:
            contact.thumbnailFile = localContact.thumbnailFile
            return .contact(contact)
        case (.music(let localMusic), .music(var music)) where isSameItem(localMusic, music):
            music.artworkFile = localMusic.artworkFile
            music.libraryID = localMusic.libraryID
            return .music(music)
        default:
            return incoming
        }
    }

    /// O cartão sem as partes locais: sem frases curtas, e com o link e a música sem arquivos (inclusive os embutidos numa nota).
    /// O estado da prévia volta ao neutro de "ainda não buscada" (`LinkPreviewState.pending`); o resto fica como está.
    public static func shared(_ item: BoardItem) -> BoardItem {
        var copy = item
        copy.keySentences = nil
        if let attachments = copy.attachments, attachments.contains(where: \.isCard) {
            copy.attachments = attachments.map { attachment in
                var attachment = attachment
                attachment.card = attachment.card.map(sharedCard)
                return attachment
            }
        }
        if var link = copy.link {
            link.previewImageFile = nil
            link.iconFile = nil
            link.preview = .pending
            copy.link = link
        }
        if var contact = copy.contact {
            contact.thumbnailFile = nil
            copy.contact = contact
        }
        if var music = copy.music {
            music.artworkFile = nil
            music.libraryID = nil
            copy.music = music
        }
        return copy
    }

    /// O cartão que chegou, com as partes locais do que este Mac já tinha quando elas ainda fazem sentido:
    /// - as frases curtas, se o registro ainda vale para o texto que chegou;
    /// - os arquivos e o estado da prévia, se os dois são link para o mesmo endereço;
    /// - a capa e o id da biblioteca, se os dois são o mesmo item de música (mesmo tipo, `catalogID` e `libraryPlaylistName`).
    ///
    /// O que não se mantém fica como em `shared(_:)`, mesmo que o cartão que chegou trouxesse algo ali. Os campos compartilhados
    /// são sempre os de `incoming`.
    public static func preservingLocalFields(of local: BoardItem?, in incoming: BoardItem) -> BoardItem {
        var result = shared(incoming)
        guard let local else { return result }

        if let record = local.keySentences, let source = NoteFolding.source(of: result), record.matches(source) {
            result.keySentences = record
        }
        if let localLink = local.link, var link = result.link, localLink.url == link.url {
            link.previewImageFile = localLink.previewImageFile
            link.iconFile = localLink.iconFile
            link.preview = localLink.preview
            result.link = link
        }
        if let localContact = local.contact, var contact = result.contact, localContact.dedupeKey == contact.dedupeKey {
            contact.thumbnailFile = localContact.thumbnailFile
            result.contact = contact
        }
        if let localMusic = local.music, var music = result.music, isSameItem(localMusic, music) {
            music.artworkFile = localMusic.artworkFile
            music.libraryID = localMusic.libraryID
            result.music = music
        }
        if let localAttachments = local.attachments, var attachments = result.attachments {
            for index in attachments.indices {
                guard let incomingCard = attachments[index].card,
                    let localCard = localAttachments.first(where: { $0.fileName == attachments[index].fileName })?.card
                else { continue }
                attachments[index].card = preservingLocalFields(ofCard: localCard, in: incomingCard)
            }
            result.attachments = attachments
        }
        return result
    }

    private static func isSameItem(_ lhs: MusicSnapshot, _ rhs: MusicSnapshot) -> Bool {
        lhs.kind == rhs.kind && lhs.catalogID == rhs.catalogID && lhs.libraryPlaylistName == rhs.libraryPlaylistName
    }
}
