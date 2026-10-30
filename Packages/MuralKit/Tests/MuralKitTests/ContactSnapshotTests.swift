import Foundation
import Testing

@testable import MuralKit

@Suite("Cartão de contato: o estado guardado")
struct ContactSnapshotTests {
    private func fullContact(thumbnail: String? = "foto.png") -> ContactSnapshot {
        ContactSnapshot(
            givenName: "Fulana", familyName: "de Tal", organization: "Empresa",
            phones: [LabeledValue(label: "celular", value: "+55 21 99999-0000")],
            emails: [LabeledValue(label: "trabalho", value: "Fulana@Example.com")], thumbnailFile: thumbnail)
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralContact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: Nome e iniciais

    @Test("O nome de exibição junta nome e sobrenome, cai na organização e por fim em Contato")
    func displayName() {
        #expect(fullContact().displayName == "Fulana de Tal")
        #expect(ContactSnapshot(givenName: " Fulana ").displayName == "Fulana")
        #expect(ContactSnapshot(familyName: "de Tal").displayName == "de Tal")
        #expect(ContactSnapshot(organization: " Empresa ").displayName == "Empresa")
        #expect(ContactSnapshot(givenName: "  ", organization: "").displayName == "Contato")
        #expect(ContactSnapshot().displayName == "Contato")
    }

    @Test("As iniciais são até duas letras maiúsculas")
    func initials() {
        #expect(fullContact().initials == "FD")
        #expect(ContactSnapshot(givenName: "ana").initials == "A")
        #expect(ContactSnapshot(organization: "Casa Nova Ltda").initials == "CN")
        #expect(ContactSnapshot().initials == "C")
    }

    @Test("Telefone e e-mail principais são os primeiros")
    func primaries() {
        #expect(fullContact().primaryPhone == "+55 21 99999-0000" && fullContact().primaryEmail == "Fulana@Example.com")
        #expect(ContactSnapshot().primaryPhone == nil && ContactSnapshot().primaryEmail == nil)
    }

    @Test("A chave de repetição usa o nome em minúsculas e o primeiro e-mail, ou o telefone na falta dele")
    func dedupeKey() {
        #expect(fullContact().dedupeKey == "fulana de tal|fulana@example.com")
        var phoneOnly = fullContact()
        phoneOnly.emails = []
        #expect(phoneOnly.dedupeKey == "fulana de tal|+55 21 99999-0000")
        #expect(ContactSnapshot(givenName: "A").dedupeKey != ContactSnapshot(givenName: "B").dedupeKey)
        #expect(fullContact(thumbnail: nil).dedupeKey == fullContact().dedupeKey)
    }

    // MARK: JSON

    @Test("Leitura tolerante: só chaves faltando valem como vazias e chaves novas são ignoradas")
    func tolerantDecoding() throws {
        let empty = try JSONDecoder().decode(ContactSnapshot.self, from: Data("{}".utf8))
        #expect(empty == ContactSnapshot())
        let json = #"{"givenName":"Ana","phones":[{"value":"123"}],"campoNovo":1}"#
        let decoded = try JSONDecoder().decode(ContactSnapshot.self, from: Data(json.utf8))
        #expect(decoded.givenName == "Ana" && decoded.phones == [LabeledValue(value: "123")] && decoded.emails.isEmpty)
        #expect(decoded.organization == nil && decoded.thumbnailFile == nil)
    }

    @Test("O cartão de contato faz a viagem de ida e volta, solto e embutido, e o JSON do cartão traz a chave contact")
    func roundTrip() throws {
        let item = BoardItem(kind: .contact, title: "Fulana de Tal", contact: fullContact())
        let data = try JSONEncoder().encode(item)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["kind"] as? String == "contact" && object["contact"] is [String: Any])
        #expect(try JSONDecoder().decode(BoardItem.self, from: data) == item)

        let id = UUID()
        let embedded = NoteAttachment(
            fileName: NoteImageMarkup.cardAttachmentName(for: id), pixelWidth: 0, pixelHeight: 0, card: .contact(fullContact()))
        let encoded = try JSONEncoder().encode(embedded)
        #expect(try JSONDecoder().decode(NoteAttachment.self, from: encoded) == embedded)
        #expect(EmbeddedCard.contact(fullContact()).title == "Fulana de Tal" && EmbeddedCard.contact(fullContact()).itemKind == .contact)
    }

    // MARK: Versão do formato

    @Test("A versão 14 só aparece com um contato, solto ou embutido")
    func formatVersion() {
        #expect(Board.currentFormatVersion == 14)
        #expect(Board(items: [BoardItem(kind: .music, title: "m")]).requiredFormatVersion == 8)
        #expect(Board(items: [BoardItem(kind: .contact, title: "c", contact: fullContact())]).requiredFormatVersion == 14)
        let embedded = NoteAttachment(
            fileName: NoteImageMarkup.cardAttachmentName(for: UUID()), pixelWidth: 0, pixelHeight: 0, card: .contact(fullContact()))
        #expect(Board(items: [BoardItem(kind: .text, title: "n", attachments: [embedded])]).requiredFormatVersion == 14)
    }

    // MARK: Compartilhamento

    @Test("A foto reduzida sai da cópia compartilhada e volta quando é a mesma pessoa; solto e embutido")
    func thumbnailIsLocal() {
        let local = BoardItem(kind: .contact, title: "c", contact: fullContact())
        let shared = SharedFieldPolicy.shared(local)
        #expect(shared.contact?.thumbnailFile == nil && shared.contact?.givenName == "Fulana")
        #expect(SharedFieldPolicy.preservingLocalFields(of: local, in: shared).contact == local.contact)

        var other = shared
        other.contact?.givenName = "Beltrana"
        #expect(SharedFieldPolicy.preservingLocalFields(of: local, in: other).contact?.thumbnailFile == nil)

        let id = NoteImageMarkup.cardAttachmentName(for: UUID())
        let note = BoardItem(
            kind: .text, title: "n",
            attachments: [NoteAttachment(fileName: id, pixelWidth: 0, pixelHeight: 0, card: .contact(fullContact()))])
        guard case .contact(let stripped)? = SharedFieldPolicy.shared(note).attachments?.first?.card else {
            Issue.record("tipo mudou")
            return
        }
        #expect(stripped.thumbnailFile == nil)
        #expect(SharedFieldPolicy.preservingLocalFields(of: note, in: SharedFieldPolicy.shared(note)).attachments == note.attachments)
        #expect(SharedFieldPolicy.scope(of: .contact) == .shared)
    }

    // MARK: Pacote

    @Test("Pacote com contato: o válido passa e os inválidos têm erro exato")
    func packageValidation() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        func check(_ item: BoardItem, expecting expected: BoardPortablePackageError?) async {
            do {
                try await service.validateBoard(Board(items: [item]), itemsURL: items)
                #expect(expected == nil, "esperado \(String(describing: expected)), passou")
            } catch {
                #expect((error as? BoardPortablePackageError) == expected)
            }
        }

        let valid = BoardItem(kind: .contact, title: "Fulana", contact: fullContact(thumbnail: nil))
        await check(valid, expecting: nil)

        var tooMany = fullContact(thumbnail: nil)
        tooMany.phones = (0...50).map { LabeledValue(value: "\($0)") }
        let many = BoardItem(kind: .contact, title: "Muitos", contact: tooMany)
        await check(many, expecting: .invalidContact(many.id))

        let badThumb = BoardItem(kind: .contact, title: "Foto", contact: fullContact(thumbnail: "../fora.png"))
        await check(badThumb, expecting: .invalidContact(badThumb.id))

        var longName = fullContact(thumbnail: nil)
        longName.givenName = String(repeating: "a", count: 1_001)
        let long = BoardItem(kind: .contact, title: "Longo", contact: longName)
        await check(long, expecting: .invalidContact(long.id))

        let missing = BoardItem(kind: .contact, title: "Sem dados")
        await check(missing, expecting: .invalidContact(missing.id))

        let stray = BoardItem(kind: .sticky, title: "Post-it", contact: fullContact(thumbnail: nil))
        await check(stray, expecting: .invalidContact(stray.id))

        func note(_ contact: ContactSnapshot) -> BoardItem {
            BoardItem(
                kind: .text, title: "n",
                attachments: [
                    NoteAttachment(
                        fileName: NoteImageMarkup.cardAttachmentName(for: UUID()), pixelWidth: 0, pixelHeight: 0, card: .contact(contact))
                ])
        }
        await check(note(fullContact(thumbnail: nil)), expecting: nil)
        let badEmbedded = note(tooMany)
        await check(badEmbedded, expecting: .invalidContact(badEmbedded.id))
    }

    @Test("A importação tira a foto reduzida do contato, solto e embutido, e recusa texto enorme")
    func normalizer() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let embedded = NoteAttachment(
            fileName: NoteImageMarkup.cardAttachmentName(for: UUID()), pixelWidth: 0, pixelHeight: 0, card: .contact(fullContact()))
        let loose = BoardItem(kind: .contact, title: "c", contact: fullContact())
        let note = BoardItem(kind: .text, title: "n", attachments: [embedded])
        let result = try BoardImportNormalizer.normalize(Board(items: [loose, note]), itemsURL: root)
        #expect(result.items[0].contact?.thumbnailFile == nil && result.items[0].contact?.givenName == "Fulana")
        guard case .contact(let stripped)? = result.items[1].attachments?.first?.card else {
            Issue.record("tipo mudou")
            return
        }
        #expect(stripped.thumbnailFile == nil && stripped.familyName == "de Tal")

        var huge = fullContact(thumbnail: nil)
        huge.organization = String(repeating: "a", count: BoardImportNormalizer.maximumTextBytes + 1)
        let big = BoardItem(kind: .contact, title: "g", contact: huge)
        #expect(throws: BoardPortablePackageError.textTooLarge(big.id)) {
            _ = try BoardImportNormalizer.normalize(Board(items: [big]), itemsURL: root)
        }
    }

    // MARK: Modelo

    @Test("Importar contatos cria um cartão por pessoa, sem repetidos do lote, com o nome como título")
    @MainActor
    func importContacts() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = BoardModel(board: Board(), store: BoardStore(directory: root), persistence: .immediate)
        let created = model.importContacts([fullContact(), fullContact(), ContactSnapshot(organization: "Empresa")])
        #expect(created.count == 2)
        #expect(created.map(\.title) == ["Fulana de Tal", "Empresa"])
        #expect(created.allSatisfy { $0.kind == .contact && $0.contact != nil })
        #expect(model.board.items.count == 2)
        #expect(model.referencedLinkPreviewFiles == ["foto.png"])
    }
}
