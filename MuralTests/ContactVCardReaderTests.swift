import AppKit
import ImageIO
import MuralKit
import Testing

@testable import Mural
@testable import MuralKit

@MainActor
@Suite("Leitor de vCard")
struct ContactVCardReaderTests {
    private static let vCard = """
        BEGIN:VCARD
        VERSION:3.0
        N:de Tal;Fulana;;;
        FN:Fulana de Tal
        ORG:Empresa
        TEL;TYPE=CELL:+55 21 99999-0000
        EMAIL;TYPE=WORK:fulana@example.com
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        N:de Tal;Fulana;;;
        FN:Fulana de Tal
        TEL:+55 21 99999-0000
        EMAIL:fulana@example.com
        END:VCARD
        BEGIN:VCARD
        VERSION:3.0
        N:;;;;
        FN:Marcenaria Silva
        ORG:Marcenaria Silva
        END:VCARD
        """

    @Test(
        "Um vCard com vários contatos vira um rascunho por pessoa, sem repetidos (3 cartões, 2 pessoas), com nome, organização, telefone e e-mail"
    )
    func mapsContacts() {
        let drafts = ContactVCardReader.drafts(fromVCard: Data(Self.vCard.utf8))
        #expect(drafts.count == 2)
        let first = drafts[0].snapshot
        #expect(first.givenName == "Fulana" && first.familyName == "de Tal" && first.organization == "Empresa")
        #expect(first.phones.map(\.value) == ["+55 21 99999-0000"] && first.emails.map(\.value) == ["fulana@example.com"])
        #expect(first.displayName == "Fulana de Tal")
        #expect(drafts.contains { $0.snapshot.displayName == "Marcenaria Silva" })
    }

    @Test("Dado que não é vCard, vazio ou grande demais não devolve nada")
    func rejectsGarbage() {
        #expect(ContactVCardReader.drafts(fromVCard: Data()).isEmpty)
        #expect(ContactVCardReader.drafts(fromVCard: Data("isto não é um vCard".utf8)).isEmpty)
    }

    @Test("A área de transferência com public.vcard dá contatos e o painel enxerga a contagem")
    func readsFromThePasteboard() {
        let pasteboard = NSPasteboard(name: .init("mural-teste-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(Data(Self.vCard.utf8), forType: ContactVCardReader.vCardType)
        let drafts = ContactVCardReader.drafts(from: pasteboard)
        #expect(!drafts.isEmpty)

        let reader = ClipboardReader(pasteboard: pasteboard, accessBehavior: { _ in .alwaysAllow })
        let reading = reader.read()
        #expect(reading.state == .available(.contact(count: drafts.count)))
        #expect(PasteDescription.noun(for: .contact(count: 1)) == "contato")
        #expect(PasteDescription.noun(for: .contact(count: 3)) == "3 contatos")
    }

    // MARK: Limites, foto e arquivos

    private static let tinyPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg=="

    @Test("Mais de 50 telefones são cortados já na leitura e o cartão passa na validação do pacote")
    func limitsValues() async throws {
        let phones = (0..<60).map { "TEL:+55 21 90000-\(String(format: "%04d", $0))" }.joined(separator: "\n")
        let vCard = "BEGIN:VCARD\nVERSION:3.0\nN:Muitos;Telefones;;;\nFN:Telefones Muitos\n\(phones)\nEND:VCARD\n"
        let draft = try #require(ContactVCardReader.drafts(fromVCard: Data(vCard.utf8)).first)
        #expect(draft.snapshot.phones.count == 50)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralContactLimit-\(UUID().uuidString)")
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let item = BoardItem(kind: .contact, title: draft.snapshot.displayName, contact: draft.snapshot)
        try await BoardPortablePackageService(availableCapacity: { _ in nil }).validateBoard(Board(items: [item]), itemsURL: items)
    }

    @Test("A foto do vCard vem em thumbnailData e o ImageIO a decodifica")
    func readsPhoto() throws {
        let vCard = "BEGIN:VCARD\nVERSION:3.0\nN:Foto;Com;;;\nFN:Com Foto\nPHOTO;ENCODING=b;TYPE=PNG:\(Self.tinyPNG)\nEND:VCARD\n"
        let draft = try #require(ContactVCardReader.drafts(fromVCard: Data(vCard.utf8)).first)
        let data = try #require(draft.thumbnailData)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(source, 0, nil) != nil)
    }

    @Test("Arquivos .vcf copiados viram contatos só quando todos os arquivos são vCards")
    func vcfFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralVcf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vcf = directory.appendingPathComponent("pessoa.vcf")
        try Data(Self.vCard.utf8).write(to: vcf)
        let png = directory.appendingPathComponent("foto.png")
        try Data("não é de verdade".utf8).write(to: png)

        let only = NSPasteboard(name: .init("mural-teste-\(UUID().uuidString)"))
        only.clearContents()
        only.writeObjects([vcf as NSURL])
        #expect(ContactVCardReader.drafts(from: only).count == 2)

        let mixed = NSPasteboard(name: .init("mural-teste-\(UUID().uuidString)"))
        mixed.clearContents()
        mixed.writeObjects([vcf as NSURL, png as NSURL])
        #expect(ContactVCardReader.drafts(from: mixed).isEmpty)
    }

    @Test("A cadeia de discagem mantém só o discável e para na primeira letra")
    func dialing() {
        #expect(ContactDialing.dialString("3333-4444 ramal 12") == "33334444")
        #expect(ContactDialing.dialString("+55 (21) 99999-0000") == "+5521999990000")
        #expect(ContactDialing.dialString("*21#,1;2") == "*21#,1;2")
        #expect(ContactDialing.dialString("ramal") == nil)
        #expect(ContactDialing.dialString("٣٣٣") == nil)
        #expect(ContactDialing.telURL("+55 21 9")?.absoluteString == "tel:+55219")
        #expect(ContactDialing.mailURL(" a b@example.com ")?.absoluteString == "mailto:a%20b@example.com")
        #expect(ContactDialing.mailURL("  ") == nil)
    }
}
