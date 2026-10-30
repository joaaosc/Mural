import AppKit
import Contacts
import Foundation
import MuralKit
import UniformTypeIdentifiers

/// Um contato lido de um vCard, com a foto quando ela veio junto.
struct ContactDraft: Equatable, Sendable {
    var snapshot: ContactSnapshot
    /// Foto como veio no vCard; o `ContactThumbnailStore` a reduz e guarda ao criar o cartão.
    var thumbnailData: Data?
}

/// Lê os contatos de um vCard copiado ou arrastado (`public.vcard` ou um arquivo `.vcf`).
///
/// A leitura é só em memória, pelo `CNContactVCardSerialization`: o Mural nunca consulta o app Contatos (`CNContactStore`) e
/// por isso não pede permissão nem entitlement. O que o vCard não traz fica de fora.
enum ContactVCardReader {
    static let vCardType = NSPasteboard.PasteboardType(UTType.vCard.identifier)

    /// Tipos que habilitam Colar quando o vCard vem sozinho.
    static let pasteTypes: [UTType] = [.vCard]

    /// Máximo de contatos devolvidos por leitura.
    static let maximumContacts = 200
    /// Maior vCard (em bytes) que se tenta ler.
    static let maximumBytes = 32 * 1024 * 1024

    /// Os contatos da área de transferência, sem repetir (`ContactSnapshot.dedupeKey`), na ordem da primeira ocorrência.
    /// Lê o dado `public.vcard` de cada item e os arquivos `.vcf` copiados.
    ///
    /// Arquivos só valem como contatos quando TODOS os arquivos copiados são vCards; com qualquer outro arquivo junto (uma
    /// imagem, por exemplo), não há contatos e a importação comum de arquivos cuida da seleção inteira.
    static func drafts(from pasteboard: NSPasteboard) -> [ContactDraft] {
        var found: [ContactDraft] = []
        for item in pasteboard.pasteboardItems ?? [] {
            if let data = item.data(forType: vCardType) { found += drafts(fromVCard: data) }
            if found.count >= maximumContacts { break }
        }
        if found.isEmpty {
            let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
            if !urls.isEmpty, urls.allSatisfy(isVCardFile) {
                for url in urls {
                    if let data = fileData(at: url) { found += drafts(fromVCard: data) }
                    if found.count >= maximumContacts { break }
                }
            }
        }
        return unique(found)
    }

    /// Os contatos de um vCard (um ou vários); vazio se o dado não é um vCard legível ou passa de 32 MB.
    static func drafts(fromVCard data: Data) -> [ContactDraft] {
        guard !data.isEmpty, data.count <= maximumBytes,
            let contacts = try? CNContactVCardSerialization.contacts(with: data)
        else { return [] }
        return unique(contacts.prefix(maximumContacts).map(draft(from:)))
    }

    /// Telefones e e-mails guardados por contato.
    static let maximumValues = 50
    /// Caracteres de cada texto guardado (nome, organização, valor e etiqueta): o mesmo teto que a validação do pacote usa, para o
    /// cartão nunca ser recusado ao exportar nem passar do limite de um campo do iCloud.
    static let maximumCharacters = 1_000

    /// O contato como o Mural o guarda. Nome e sobrenome ficam separados; as etiquetas saem localizadas. Os limites
    /// (`maximumValues`, `maximumCharacters`) valem já aqui, na leitura.
    static func draft(from contact: CNContact) -> ContactDraft {
        let organization = clipped(contact.organizationName)
        let snapshot = ContactSnapshot(
            givenName: clipped(contact.givenName),
            familyName: clipped(contact.familyName),
            organization: organization.isEmpty ? nil : organization,
            phones: contact.phoneNumbers.prefix(maximumValues).map {
                LabeledValue(label: label(of: $0.label), value: clipped($0.value.stringValue))
            },
            emails: contact.emailAddresses.prefix(maximumValues).map {
                LabeledValue(label: label(of: $0.label), value: clipped($0.value as String))
            })
        let thumbnail = contact.isKeyAvailable(CNContactImageDataKey) ? contact.imageData : nil
        return ContactDraft(snapshot: snapshot, thumbnailData: thumbnail)
    }

    // MARK: Interno

    private static func label(of raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let localized = CNLabeledValue<NSString>.localizedString(forLabel: raw)
        return localized.isEmpty ? nil : clipped(localized)
    }

    private static func clipped(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumCharacters))
    }

    private static func isVCardFile(_ url: URL) -> Bool {
        url.isFileURL && ["vcf", "vcard"].contains(url.pathExtension.lowercased())
    }

    private static func fileData(at url: URL) -> Data? {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size > 0, size <= maximumBytes else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func unique(_ drafts: [ContactDraft]) -> [ContactDraft] {
        var seen = Set<String>()
        return drafts.filter { seen.insert($0.snapshot.dedupeKey).inserted }.prefix(maximumContacts).map { $0 }
    }
}
