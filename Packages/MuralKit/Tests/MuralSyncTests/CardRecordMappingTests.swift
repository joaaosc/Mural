import Foundation
import MuralKit
import MuralSync
import Testing

@Suite("iCloud: tradução entre cartão e registro")
struct CardRecordMappingTests {
    private static let fixedID = UUID(uuidString: "5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01")!

    /// O cartão e o empilhamento que o registro dá, ou `nil` se ele não é suportado.
    private func decodedCard(_ record: CloudRecord) throws -> (item: BoardItem, layer: Double?)? {
        guard case .card(let item, let layer) = try CardRecordMapping.card(from: record) else { return nil }
        return (item, layer)
    }

    /// A mensagem do `invalidRecord` que o registro causa.
    private func invalidMessage(of record: CloudRecord) throws -> String {
        let error = try #require(throws: CardRecordMappingError.self) { try CardRecordMapping.card(from: record) }
        guard case .invalidRecord(let message) = error else {
            Issue.record("esperava invalidRecord, veio \(error)")
            return ""
        }
        return message
    }

    private func jsonObject(_ value: CloudValue?) throws -> [String: Any] {
        guard case .data(let data)? = value else {
            Issue.record("esperava um campo de dados, veio \(String(describing: value))")
            return [:]
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Cartão: ida e volta

    @Test("Cartão de cada tipo, com todos os campos preenchidos, volta igual na forma compartilhada", arguments: ItemKind.allCases)
    func everyKindRoundTrips(kind: ItemKind) throws {
        let item = SyncFixtures.fullItem(kind: kind)
        let fields = try CardRecordMapping.fields(for: item, layer: 7.25)
        let record = SyncFixtures.record(.card, name: item.id.uuidString, fields: fields)

        let decoded = try #require(try decodedCard(record))

        #expect(decoded.item == SharedFieldPolicy.shared(item))
        #expect(decoded.item.id == item.id)
        #expect(decoded.layer == 7.25)
        // Nada a reenviar: o que este Mac mandaria de novo é o que o iCloud já tem.
        #expect(try CardRecordMapping.fields(for: decoded.item, layer: 7.25) == fields)
    }

    @Test("O cartão completo preenche todos os campos do registro de cartão")
    func fullItemFillsEveryCardField() throws {
        let fields = try CardRecordMapping.fields(for: SyncFixtures.fullItem(kind: .image), layer: 1)

        let cardKeys = Set(CloudSchema.Key.allCases.map(\.rawValue)).subtracting(["name", "file", "cardID"])
        #expect(Set(fields.keys) == cardKeys)
        #expect(fields["parentID"] == .string("11111111-2222-3333-4444-555555555555"))
        #expect(fields["folderX"] == .double(-12) && fields["folderY"] == .double(48.5))
        #expect(fields["x"] == .double(120.5) && fields["y"] == .double(-33.25))
        #expect(fields["stickyColor"] == .string("pink") && fields["colorTag"] == .string("purple"))
        #expect(fields["kind"] == .string("image") && fields["tag"] == .string("CLIENT 001"))
    }

    @Test(
        "Datas com fração viajam sem perder nenhum bit, no campo do cartão e dentro do JSON do lembrete",
        arguments: [0.0, 0.1, 779_123_456.123_456_789, 779_123_456.0.nextUp, -62_135_769_600.5, 4_102_444_800.999_999, 1.0e-7])
    func datesRoundTripBitForBit(seconds: Double) throws {
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        let reminder = ReminderSnapshot(identifier: "r", title: "t", dueDate: date, completionDate: date)
        let item = BoardItem(kind: .reminder, title: "Data", createdAt: date, reminder: reminder)
        let record = try SyncFixtures.cardRecord(item)

        #expect(record.fields["createdAt"] == .double(seconds))
        let decoded = try #require(try decodedCard(record)).item
        #expect(decoded.createdAt.timeIntervalSinceReferenceDate.bitPattern == seconds.bitPattern)
        #expect(decoded.reminder?.dueDate?.timeIntervalSinceReferenceDate.bitPattern == seconds.bitPattern)
        #expect(decoded.reminder?.completionDate?.timeIntervalSinceReferenceDate.bitPattern == seconds.bitPattern)
    }

    @Test("Campo sem valor fica de fora do registro, e o cartão mínimo volta igual")
    func nilFieldsAreAbsent() throws {
        let item = BoardItem(
            id: Self.fixedID, kind: .sticky, title: "Tinta", createdAt: SyncFixtures.fractionalDate, position: BoardPoint(x: 10, y: 20))

        let fields = try CardRecordMapping.fields(for: item, layer: 3)

        #expect(Set(fields.keys) == ["kind", "title", "createdAt", "x", "y", "layer", "formatVersion"])
        #expect(fields["kind"] == .string("sticky") && fields["title"] == .string("Tinta"))
        #expect(fields["layer"] == .double(3) && fields["formatVersion"] == .int(1))
        let record = SyncFixtures.record(.card, name: item.id.uuidString, fields: fields)
        let decoded = try #require(try decodedCard(record))
        #expect(decoded.item == item)
        #expect(decoded.layer == 3)
    }

    @Test("Texto, legenda, etiqueta e anexos vazios são valores, não ausência, e voltam como estavam")
    func emptyValuesStayDistinctFromNil() throws {
        let item = BoardItem(id: Self.fixedID, kind: .text, title: "", text: "", caption: "", tag: "", attachments: [])
        let fields = try CardRecordMapping.fields(for: item, layer: 0)

        #expect(fields["title"] == .string("") && fields["text"] == .string("") && fields["caption"] == .string(""))
        #expect(fields["tag"] == .string("") && fields["attachments"] != nil)
        let record = SyncFixtures.record(.card, name: item.id.uuidString, fields: fields)
        #expect(try decodedCard(record)?.item == item)
    }

    @Test("Cartão embutido numa nota viaja no registro sem as partes locais do link")
    func embeddedCardRoundTrips() throws {
        let link = LinkInfo(
            url: URL(string: "https://example.com")!, pageTitle: "Exemplo", previewImageFile: "p.jpg", preview: .ready(fetchedAt: .now))
        let attachment = NoteAttachment(fileName: "\(UUID().uuidString).card", pixelWidth: 0, pixelHeight: 0, card: .link(link))
        let item = BoardItem(id: Self.fixedID, kind: .text, title: "n", text: "t", attachments: [attachment])
        let fields = try CardRecordMapping.fields(for: item, layer: 0)
        #expect(fields["formatVersion"] == .int(13))
        let record = SyncFixtures.record(.card, name: item.id.uuidString, fields: fields)
        let decoded = try #require(try decodedCard(record)).item
        #expect(decoded == SharedFieldPolicy.shared(item))
        guard case .link(let received)? = decoded.attachments?.first?.card else {
            Issue.record("tipo mudou")
            return
        }
        #expect(received.previewImageFile == nil && received.preview == .pending && received.pageTitle == "Exemplo")
    }

    @Test("Anexo com nome e conteúdo de cartão incoerentes, ou link embutido que não é http, é registro inválido")
    func incoherentEmbeddedCardsAreInvalid() throws {
        let valid = try SyncFixtures.cardRecord(SyncFixtures.fullItem(kind: .text))
        let reminder = EmbeddedCard.reminder(ReminderSnapshot(identifier: "", title: "r"))
        let cardName = "\(UUID().uuidString).card"
        let cases: [(String, NoteAttachment)] = [
            ("png com cartão", NoteAttachment(fileName: "\(UUID().uuidString).png", pixelWidth: 0, pixelHeight: 0, card: reminder)),
            ("card sem cartão", NoteAttachment(fileName: cardName, pixelWidth: 0, pixelHeight: 0)),
            (
                "link ftp",
                NoteAttachment(
                    fileName: cardName, pixelWidth: 0, pixelHeight: 0, card: .link(LinkInfo(url: URL(string: "ftp://exemplo.com/a")!)))
            ),
        ]
        for (name, attachment) in cases {
            var record = valid
            record.fields["attachments"] = .data(try JSONEncoder().encode([attachment]))
            #expect(!(try invalidMessage(of: record)).isEmpty, "\(name)")
        }
    }

    @Test("O mesmo cartão dá sempre os mesmos campos, byte a byte, e o empilhamento acompanha o número dado")
    func fieldsAreDeterministic() throws {
        let item = SyncFixtures.fullItem(kind: .link)

        let first = try CardRecordMapping.fields(for: item, layer: 2)
        let second = try CardRecordMapping.fields(for: item, layer: 2)
        let other = try CardRecordMapping.fields(for: item, layer: 2.5)

        #expect(first == second)
        #expect(other["layer"] == .double(2.5))
        #expect(first.filter { $0.key != "layer" } == other.filter { $0.key != "layer" })
    }

    @Test("O número de empilhamento vai no registro e volta; sem ele o cartão vem sem layer")
    func layerTravelsAlongside() throws {
        let item = BoardItem(kind: .sticky, title: "Tinta")
        var record = try SyncFixtures.cardRecord(item, layer: 12.5)

        #expect(record.fields["layer"] == .double(12.5))
        #expect(try #require(try decodedCard(record)).layer == 12.5)

        record.fields["layer"] = nil
        let withoutLayer = try #require(try decodedCard(record))
        #expect(withoutLayer.layer == nil)
        #expect(withoutLayer.item == item)
    }

    // MARK: Cartão: o que não viaja

    @Test("As frases curtas e as partes locais de link e música não viajam, nem no campo nem dentro do JSON")
    func localPartsDoNotTravel() throws {
        let item = SyncFixtures.fullItem(kind: .link)
        let fields = try CardRecordMapping.fields(for: item, layer: 1)

        #expect(fields["keySentences"] == nil)
        let link = try jsonObject(fields["link"])
        #expect(link["previewImageFile"] == nil && link["iconFile"] == nil)
        #expect(link["url"] as? String == "https://example.com/a?b=c#d")
        #expect(link["pageTitle"] as? String == "Página de exemplo" && link["siteName"] as? String == "Exemplo")
        #expect(link["summary"] as? String == "Resumo da página" && link["remoteImageURL"] as? String == "https://example.com/i.png")
        let music = try jsonObject(fields["music"])
        #expect(music["artworkFile"] == nil && music["libraryID"] == nil)
        #expect(music["catalogID"] as? String == "1234" && music["libraryPlaylistName"] as? String == "Minha lista")
        #expect(music["artworkTemplate"] as? String == "https://example.com/{w}x{h}.{f}")

        // Nem a data da última busca da prévia: o estado dela volta ao neutro.
        if case .data(let bytes)? = fields["link"] {
            #expect(!String(decoding: bytes, as: UTF8.self).contains("fetchedAt"))
        }
        let record = SyncFixtures.record(.card, name: item.id.uuidString, fields: fields)
        let decoded = try #require(try decodedCard(record)).item
        #expect(decoded.keySentences == nil)
        #expect(decoded.link?.preview == .pending)
        #expect(decoded.link?.previewImageFile == nil && decoded.link?.iconFile == nil)
        #expect(decoded.link?.url == item.link?.url && decoded.link?.pageTitle == "Página de exemplo")
        #expect(decoded.music?.artworkFile == nil && decoded.music?.libraryID == nil)
        #expect(decoded.music?.catalogID == "1234" && decoded.music?.duration == 215.123_456)
    }

    @Test("Passar o cartão já na forma compartilhada ou deixar a função aplicá-la dá os mesmos campos")
    func sharedFormIsAppliedAgain() throws {
        let item = SyncFixtures.fullItem(kind: .music)

        let direct = try CardRecordMapping.fields(for: item, layer: 2)
        let alreadyShared = try CardRecordMapping.fields(for: SharedFieldPolicy.shared(item), layer: 2)

        #expect(direct == alreadyShared)
    }

    @Test("Um registro com partes locais, de um escritor que não as tirou, volta na forma compartilhada")
    func decodingDropsLocalParts() throws {
        let item = SyncFixtures.fullItem(kind: .link)
        var record = try SyncFixtures.cardRecord(item)
        record.fields["link"] = .data(try JSONEncoder().encode(item.link))
        record.fields["music"] = .data(try JSONEncoder().encode(item.music))

        let decoded = try #require(try decodedCard(record)).item

        #expect(decoded == SharedFieldPolicy.shared(item))
        #expect(decoded.link?.preview == .pending && decoded.link?.iconFile == nil)
        #expect(decoded.music?.artworkFile == nil && decoded.music?.libraryID == nil)
    }

    // MARK: Cartão: versão do formato

    @Test("A versão do formato do registro é a que o cartão exige")
    func recordFormatVersion() throws {
        let attachment = NoteAttachment(fileName: "a.png", pixelWidth: 1, pixelHeight: 1)
        let cases: [(name: String, item: BoardItem, version: Int)] = [
            ("post-it simples", BoardItem(kind: .sticky, title: "a"), 1),
            ("pasta dentro de pasta", BoardItem(kind: .folder, title: "Sub", parentID: UUID()), 2),
            ("link", BoardItem(kind: .link, title: "l", link: LinkInfo(url: URL(string: "https://example.com")!)), 3),
            ("cor", BoardItem(kind: .sticky, title: "c", colorTag: .red), 4),
            ("anexo", BoardItem(kind: .text, title: "n", attachments: [attachment]), 5),
            ("lembrete", BoardItem(kind: .reminder, title: "r"), 6),
            ("música", BoardItem(kind: .music, title: "m"), 8),
            ("lugar na pasta", BoardItem(kind: .sticky, title: "p", parentID: UUID(), folderPosition: BoardPoint(x: 1, y: 2)), 9),
            ("legenda", BoardItem(kind: .image, title: "i", caption: "legenda"), 10),
            ("tamanho", BoardItem(kind: .sticky, title: "t", size: BoardSize(width: 200, height: 150)), 11),
            ("tamanho de imagem", BoardItem(kind: .image, title: "i", size: BoardSize(width: 200, height: 150)), 12),
            (
                "cartão embutido",
                BoardItem(
                    kind: .text, title: "n",
                    attachments: [
                        NoteAttachment(
                            fileName: "\(UUID().uuidString).card", pixelWidth: 0, pixelHeight: 0,
                            card: .reminder(ReminderSnapshot(identifier: "", title: "r")))
                    ]), 13
            ),
        ]
        for (name, item, version) in cases {
            let fields = try CardRecordMapping.fields(for: item, layer: 0)
            #expect(fields["formatVersion"] == .int(Int64(version)), "\(name)")
            #expect(version == Board(items: [item]).requiredFormatVersion, "\(name)")
        }

        let full = try CardRecordMapping.fields(for: SyncFixtures.fullItem(kind: .text), layer: 0)
        #expect(full["formatVersion"] == .int(Int64(Board(items: [SyncFixtures.fullItem(kind: .text)]).requiredFormatVersion)))
    }

    @Test("Registro de tipo de cartão desconhecido ou de versão futura não é suportado, e isso não é erro")
    func newerAppRecordsAreUnsupported() throws {
        let valid = try SyncFixtures.cardRecord(BoardItem(kind: .sticky, title: "Tinta"))

        var unknownKind = valid
        unknownKind.fields["kind"] = .string("holograma")
        #expect(try CardRecordMapping.card(from: unknownKind) == .unsupported)

        var future = valid
        future.fields["formatVersion"] = .int(Int64(Board.currentFormatVersion + 1))
        #expect(try CardRecordMapping.card(from: future) == .unsupported)

        // A versão decide antes do resto: um app mais novo pode ter tirado ou mudado qualquer campo.
        var reshaped = future
        reshaped.fields["title"] = nil
        reshaped.fields["x"] = .string("mudou de tipo")
        reshaped.fields["checklist"] = .data(Data("não é JSON".utf8))
        #expect(try CardRecordMapping.card(from: reshaped) == .unsupported)

        // A versão que esta build escreve ainda é lida.
        var current = valid
        current.fields["formatVersion"] = .int(Int64(Board.currentFormatVersion))
        #expect(try CardRecordMapping.card(from: current) != .unsupported)
    }

    @Test("Cor de post-it ou de etiqueta que esta build não conhece também não é suportada")
    func unknownColorsAreUnsupported() throws {
        let valid = try SyncFixtures.cardRecord(SyncFixtures.fullItem(kind: .sticky))
        for key in ["stickyColor", "colorTag"] {
            var record = valid
            record.fields[key] = .string("ultravioleta")
            #expect(try CardRecordMapping.card(from: record) == .unsupported, "\(key)")
        }
    }

    // MARK: Cartão: registros inválidos

    @Test("Campo obrigatório ausente é registro inválido, e a mensagem diz qual", arguments: ["kind", "title", "createdAt", "x", "y"])
    func missingRequiredFieldIsInvalid(key: String) throws {
        var record = try SyncFixtures.cardRecord(BoardItem(kind: .sticky, title: "Tinta"))
        record.fields[key] = nil

        #expect(try invalidMessage(of: record).contains(key))
    }

    @Test("Campo com o tipo errado é registro inválido, também nos opcionais")
    func wrongTypeIsInvalid() throws {
        let valid = try SyncFixtures.cardRecord(SyncFixtures.fullItem(kind: .text))
        let wrong: [(key: String, value: CloudValue)] = [
            ("kind", .double(1)), ("title", .int(1)), ("createdAt", .string("ontem")), ("x", .int(3)), ("y", .data(Data())),
            ("layer", .string("alto")), ("formatVersion", .string("10")), ("parentID", .double(2)), ("folderX", .string("1")),
            ("fileName", .int(1)), ("text", .data(Data())), ("caption", .double(1)), ("tag", .int(3)), ("stickyColor", .int(1)),
            ("colorTag", .double(1)), ("checklist", .string("{}")), ("link", .int(1)), ("attachments", .asset(URL(fileURLWithPath: "/x"))),
        ]
        for (key, value) in wrong {
            var record = valid
            record.fields[key] = value
            #expect(try invalidMessage(of: record).contains(key), "\(key)")
        }
    }

    @Test("JSON ilegível, UUID inválido e par de posição incompleto são registros inválidos")
    func malformedValuesAreInvalid() throws {
        let valid = try SyncFixtures.cardRecord(SyncFixtures.fullItem(kind: .text))
        func message(setting key: String, to value: CloudValue?) throws -> String {
            var record = valid
            record.fields[key] = value
            return try invalidMessage(of: record)
        }

        for key in ["checklist", "imageMetadata", "link", "reminder", "music", "attachments"] {
            #expect(try message(setting: key, to: .data(Data("{".utf8))).contains(key), "\(key): JSON cortado")
            #expect(try message(setting: key, to: .data(Data())).contains(key), "\(key): vazio")
        }
        #expect(try message(setting: "attachments", to: .data(Data("{}".utf8))).contains("attachments"))
        #expect(try message(setting: "reminder", to: .data(Data("[]".utf8))).contains("reminder"))
        #expect(try message(setting: "parentID", to: .string("não é um UUID")).contains("parentID"))
        #expect(try message(setting: "folderX", to: nil).contains("folderX"))
        #expect(try message(setting: "folderY", to: nil).contains("folderY"))
    }

    @Test("Nome de arquivo que sairia de Items/ é registro inválido, no cartão e nos anexos")
    func unsafeFileNamesAreInvalid() throws {
        let valid = try SyncFixtures.cardRecord(SyncFixtures.fullItem(kind: .image))
        for name in ["../segredo.jpg", "/etc/passwd", "pasta/foto.jpg", ".oculto", "a:b.png", "..", ""] {
            var record = valid
            record.fields["fileName"] = .string(name)
            #expect(try invalidMessage(of: record).contains("Items"), "fileName \(name)")

            var attached = valid
            let attachments = [NoteAttachment(fileName: name, pixelWidth: 1, pixelHeight: 1)]
            attached.fields["attachments"] = .data(try JSONEncoder().encode(attachments))
            #expect(try invalidMessage(of: attached).contains("Items"), "anexo \(name)")
        }
        var plain = valid
        plain.fields["fileName"] = .string("Foto de férias 1.jpg")
        #expect(try decodedCard(plain)?.item.fileName == "Foto de férias 1.jpg")
    }

    @Test("O nome do registro precisa ser o uuidString do cartão, e o tipo precisa ser Card")
    func recordIdentityIsChecked() throws {
        let item = BoardItem(id: Self.fixedID, kind: .sticky, title: "Tinta")
        let fields = try CardRecordMapping.fields(for: item, layer: 1)

        for name in ["", "tinta", Self.fixedID.uuidString.lowercased(), Self.fixedID.uuidString + "-2", " " + Self.fixedID.uuidString] {
            let record = SyncFixtures.record(.card, name: name, fields: fields)
            #expect(try invalidMessage(of: record).contains("UUID"), "nome \(name)")
        }
        let wrongType = SyncFixtures.record(.freeText, name: Self.fixedID.uuidString, fields: fields)
        #expect(try invalidMessage(of: wrongType).contains("FreeText"))
        #expect(try decodedCard(SyncFixtures.record(.card, name: Self.fixedID.uuidString, fields: fields))?.item == item)
    }

    // MARK: Cartão: tamanho

    @Test("Texto que passa do limite é recusado com o id do cartão, também dentro do JSON")
    func hugeContentIsRefused() throws {
        #expect(CardRecordMapping.maximumFieldBytes == 900_000)

        let huge = BoardItem(kind: .text, title: "Longa", text: String(repeating: "a", count: 1_000_000))
        #expect(throws: CardRecordMappingError.recordTooLarge(huge.id)) { try CardRecordMapping.fields(for: huge, layer: 1) }

        let entry = ChecklistEntry(text: String(repeating: "b", count: 1_000_000))
        let list = ChecklistDocument(title: "Longa", sections: [ChecklistSection(title: "Tudo", entries: [entry])])
        let hugeList = BoardItem(kind: .checklist, title: "Lista longa", checklist: list)
        #expect(throws: CardRecordMappingError.recordTooLarge(hugeList.id)) { try CardRecordMapping.fields(for: hugeList, layer: 1) }
    }

    @Test("O limite conta bytes em UTF-8 e não caracteres")
    func limitCountsUTF8Bytes() throws {
        // 450 mil "é" são 450 mil caracteres, mas 900 mil bytes; com o título e o resto passam do limite.
        let accented = BoardItem(kind: .text, title: "Acentos", text: String(repeating: "é", count: 450_000))

        #expect(throws: CardRecordMappingError.recordTooLarge(accented.id)) { try CardRecordMapping.fields(for: accented, layer: 1) }
    }

    @Test("Exatamente no limite o cartão passa, e um byte a mais é recusado")
    func limitBoundary() throws {
        func item(textBytes: Int) -> BoardItem {
            BoardItem(id: Self.fixedID, kind: .text, title: "Limite", text: String(repeating: "a", count: textBytes))
        }
        let empty = try CardRecordMapping.fields(for: item(textBytes: 0), layer: 1)
        let room = CardRecordMapping.maximumFieldBytes - SyncFixtures.payloadBytes(of: empty)

        let atLimit = try CardRecordMapping.fields(for: item(textBytes: room), layer: 1)

        #expect(SyncFixtures.payloadBytes(of: atLimit) == CardRecordMapping.maximumFieldBytes)
        #expect(throws: CardRecordMappingError.recordTooLarge(Self.fixedID)) {
            try CardRecordMapping.fields(for: item(textBytes: room + 1), layer: 1)
        }
    }

    // MARK: Texto livre

    @Test("Texto livre: as quatro chaves e a versão do formato, e a ida e volta é exata")
    func freeTextRoundTrips() throws {
        let freeText = BoardFreeText(
            text: "Lembrar do leite 🥛", position: BoardPoint(x: -12.5, y: 340.125), createdAt: SyncFixtures.fractionalDate)

        let fields = CardRecordMapping.fields(for: freeText)

        #expect(Set(fields.keys) == ["text", "x", "y", "createdAt", "formatVersion"])
        #expect(fields["createdAt"] == .double(SyncFixtures.fractionalDate.timeIntervalSinceReferenceDate))
        #expect(fields["formatVersion"] == .int(7))
        let record = SyncFixtures.record(.freeText, name: freeText.id.uuidString, fields: fields)
        guard case .freeText(let decoded) = try CardRecordMapping.freeText(from: record) else {
            Issue.record("o texto livre não foi lido")
            return
        }
        #expect(decoded == freeText)
        #expect(decoded.createdAt.timeIntervalSinceReferenceDate.bitPattern == freeText.createdAt.timeIntervalSinceReferenceDate.bitPattern)
        #expect(CardRecordMapping.fields(for: decoded) == fields)
    }

    @Test("Texto livre com tamanho: largura e altura viajam juntas e a versão do formato sobe para a do tamanho")
    func freeTextSizeRoundTrips() throws {
        let freeText = BoardFreeText(
            text: "Grande", position: BoardPoint(x: 3, y: 4), createdAt: SyncFixtures.fractionalDate,
            size: BoardSize(width: 320.5, height: 180.25))

        let fields = CardRecordMapping.fields(for: freeText)

        #expect(fields["width"] == .double(320.5) && fields["height"] == .double(180.25))
        #expect(fields["formatVersion"] == .int(11))
        let record = SyncFixtures.record(.freeText, name: freeText.id.uuidString, fields: fields)
        #expect(try CardRecordMapping.freeText(from: record) == .freeText(freeText))
    }

    @Test("Texto livre de versão futura não é suportado, e um sem a versão (gravado antes dela) é lido")
    func freeTextVersionGatesTheRecord() throws {
        let freeText = BoardFreeText(id: Self.fixedID, text: "Oi", position: BoardPoint(x: 1, y: 2), createdAt: SyncFixtures.fractionalDate)
        var fields = CardRecordMapping.fields(for: freeText)

        fields["formatVersion"] = .int(Int64(Board.currentFormatVersion + 1))
        #expect(
            try CardRecordMapping.freeText(from: SyncFixtures.record(.freeText, name: Self.fixedID.uuidString, fields: fields))
                == .unsupported)

        fields["formatVersion"] = nil
        #expect(
            try CardRecordMapping.freeText(from: SyncFixtures.record(.freeText, name: Self.fixedID.uuidString, fields: fields))
                == .freeText(freeText))
    }

    @Test("Texto livre com campo ausente, de tipo errado ou com nome ou tipo de registro errado é inválido")
    func malformedFreeTextIsInvalid() throws {
        let freeText = BoardFreeText(id: Self.fixedID, text: "Oi", position: BoardPoint(x: 1, y: 2))
        let fields = CardRecordMapping.fields(for: freeText)

        func failure(of record: CloudRecord) throws -> String {
            let error = try #require(throws: CardRecordMappingError.self) { try CardRecordMapping.freeText(from: record) }
            guard case .invalidRecord(let message) = error else { return "" }
            return message
        }
        for key in ["text", "x", "y", "createdAt"] {
            var missing = fields
            missing[key] = nil
            #expect(try failure(of: SyncFixtures.record(.freeText, name: Self.fixedID.uuidString, fields: missing)).contains(key))

            var wrong = fields
            wrong[key] = .data(Data())
            #expect(try failure(of: SyncFixtures.record(.freeText, name: Self.fixedID.uuidString, fields: wrong)).contains(key))
        }
        for key in ["width", "height"] {
            var alone = fields
            alone[key] = .double(200)
            #expect(try failure(of: SyncFixtures.record(.freeText, name: Self.fixedID.uuidString, fields: alone)).contains("juntos"))
        }
        #expect(try failure(of: SyncFixtures.record(.freeText, name: "texto", fields: fields)).contains("UUID"))
        #expect(try failure(of: SyncFixtures.record(.card, name: Self.fixedID.uuidString, fields: fields)).contains("Card"))
    }

    // MARK: Mural

    @Test("Mural: o nome e a versão do formato que o conteúdo exige")
    func boardRecordCarriesNameAndVersion() {
        let sticky = Board(items: [BoardItem(kind: .sticky, title: "a")])
        let withFreeText = Board(freeTexts: [BoardFreeText(text: "oi")])
        let rich = Board(items: [SyncFixtures.fullItem(kind: .text)], freeTexts: [BoardFreeText(text: "oi")])
        let cases: [(board: Board, version: Int)] = [(Board(), 1), (sticky, 1), (withFreeText, 7), (rich, 11)]

        for (board, version) in cases {
            let fields = CardRecordMapping.boardFields(name: "Casa 🏠", board: board)

            #expect(fields == ["name": .string("Casa 🏠"), "formatVersion": .int(Int64(version))])
            let record = SyncFixtures.record(.mural, name: CloudSchema.muralRecordName, fields: fields)
            #expect(CardRecordMapping.boardName(from: record) == "Casa 🏠")
        }
    }

    @Test("A versão do mural é a que o conteúdo exige, não a que ficou gravada nele")
    func boardVersionIsTheRequiredOne() throws {
        var board = Board(freeTexts: [BoardFreeText(text: "oi")])
        board.formatVersion = 1

        let fields = CardRecordMapping.boardFields(name: "Casa", board: board)

        #expect(fields["formatVersion"] == .int(7))
    }

    @Test("Sem nome, de outro tipo ou com o nome de outro tipo de valor, o registro não dá nome de mural")
    func boardNameNeedsAMuralRecordWithAString() {
        let name = CardRecordMapping.boardFields(name: "", board: Board())
        #expect(CardRecordMapping.boardName(from: SyncFixtures.record(.mural, name: "mural", fields: name)) == "")

        #expect(CardRecordMapping.boardName(from: SyncFixtures.record(.mural, name: "mural", fields: [:])) == nil)
        #expect(CardRecordMapping.boardName(from: SyncFixtures.record(.mural, name: "mural", fields: ["name": .int(1)])) == nil)
        #expect(CardRecordMapping.boardName(from: SyncFixtures.record(.card, name: "mural", fields: name)) == nil)
    }

    // MARK: Arquivo de mídia

    @Test("Arquivo de mídia: o arquivo e o cartão dono, e o nome do arquivo é o do registro")
    func mediaFileRoundTrips() throws {
        let cardID = UUID()
        let fileName = "AAAAAAAA-0000-4000-8000-000000000001.jpg"
        let url = URL(fileURLWithPath: "/tmp/cache/\(fileName)")

        let fields = CardRecordMapping.mediaFields(fileURL: url, cardID: cardID)

        #expect(fields == ["file": .asset(url), "cardID": .string(cardID.uuidString)])
        let record = SyncFixtures.record(.mediaFile, name: fileName, fields: fields)
        let media = try #require(CardRecordMapping.mediaFile(from: record))
        #expect(media.fileName == fileName)
        #expect(media.url == url)
    }

    @Test("O cartão dono vem do campo cardID do registro de mídia, e só se for um UUID")
    func mediaCardIDComesFromTheCardIDField() {
        let cardID = UUID()
        let url = URL(fileURLWithPath: "/tmp/cache/foto.jpg")
        let fields = CardRecordMapping.mediaFields(fileURL: url, cardID: cardID)

        #expect(CardRecordMapping.mediaCardID(from: SyncFixtures.record(.mediaFile, name: "foto.jpg", fields: fields)) == cardID)
        #expect(
            CardRecordMapping.mediaCardID(from: SyncFixtures.record(.mediaFile, name: "foto.jpg", fields: ["file": .asset(url)])) == nil)
        #expect(
            CardRecordMapping.mediaCardID(from: SyncFixtures.record(.mediaFile, name: "foto.jpg", fields: ["cardID": .string("x")])) == nil)
        #expect(CardRecordMapping.mediaCardID(from: SyncFixtures.record(.mediaFile, name: "foto.jpg", fields: ["cardID": .int(1)])) == nil)
        #expect(CardRecordMapping.mediaCardID(from: SyncFixtures.record(.card, name: "foto.jpg", fields: fields)) == nil)
    }

    @Test("Registro de mídia sem arquivo, de outro tipo ou com nome que sairia de Items/ não vale")
    func invalidMediaRecordsGiveNothing() {
        let url = URL(fileURLWithPath: "/tmp/cache/foto.jpg")
        let fields = CardRecordMapping.mediaFields(fileURL: url, cardID: UUID())

        #expect(CardRecordMapping.mediaFile(from: SyncFixtures.record(.mediaFile, name: "foto.jpg", fields: fields)) != nil)
        #expect(CardRecordMapping.mediaFile(from: SyncFixtures.record(.mediaFile, name: "foto.jpg", fields: [:])) == nil)
        #expect(CardRecordMapping.mediaFile(from: SyncFixtures.record(.mediaFile, name: "foto.jpg", fields: ["file": .string("x")])) == nil)
        #expect(CardRecordMapping.mediaFile(from: SyncFixtures.record(.card, name: "foto.jpg", fields: fields)) == nil)
        for name in ["", "../foto.jpg", "pasta/foto.jpg", ".foto.jpg", "a:b.jpg", ".."] {
            #expect(CardRecordMapping.mediaFile(from: SyncFixtures.record(.mediaFile, name: name, fields: fields)) == nil, "\(name)")
        }
    }
}
