import Foundation

/// Cartão embutido numa nota: o conteúdo de um cartão de música, de lembrete, de link ou de contato guardado dentro do próprio anexo
/// (`NoteAttachment.card`) e citado no Markdown como `![título](mural-card:<UUID>)`.
///
/// O JSON tem forma estável, com o tipo em `kind` e o conteúdo numa chave de mesmo nome: `{"kind":"music","music":{…}}`.
/// Um tipo desconhecido é recusado de propósito ao decodificar: a versão do formato do mural (13 para o cartão embutido, 14 para o contato) é o que protege as builds
/// antigas, então um tipo futuro só chega a quem já o conhece.
public enum EmbeddedCard: Codable, Hashable, Sendable {
    case music(MusicSnapshot)
    case reminder(ReminderSnapshot)
    case link(LinkInfo)
    case contact(ContactSnapshot)

    private enum CodingKeys: String, CodingKey {
        case kind, music, reminder, link, contact
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "music": self = .music(try container.decode(MusicSnapshot.self, forKey: .music))
        case "reminder": self = .reminder(try container.decode(ReminderSnapshot.self, forKey: .reminder))
        case "link": self = .link(try container.decode(LinkInfo.self, forKey: .link))
        case "contact": self = .contact(try container.decode(ContactSnapshot.self, forKey: .contact))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "Tipo de cartão embutido desconhecido: \(kind)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .music(let snapshot):
            try container.encode("music", forKey: .kind)
            try container.encode(snapshot, forKey: .music)
        case .reminder(let snapshot):
            try container.encode("reminder", forKey: .kind)
            try container.encode(snapshot, forKey: .reminder)
        case .link(let info):
            try container.encode("link", forKey: .kind)
            try container.encode(info, forKey: .link)
        case .contact(let snapshot):
            try container.encode("contact", forKey: .kind)
            try container.encode(snapshot, forKey: .contact)
        }
    }

    /// Título que o cartão mostra: o da música, o do lembrete ou o da página (na falta dele, o endereço do site).
    public var title: String {
        switch self {
        case .music(let snapshot): snapshot.title
        case .reminder(let snapshot): snapshot.title
        case .link(let info): info.pageTitle ?? WebLink.displayHost(of: info.url)
        case .contact(let snapshot): snapshot.displayName
        }
    }

    /// O tipo de cartão avulso equivalente.
    public var itemKind: ItemKind {
        switch self {
        case .music: .music
        case .reminder: .reminder
        case .link: .link
        case .contact: .contact
        }
    }
}
