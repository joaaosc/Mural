import Foundation
import MuralKit
import MuralSync
import Testing

@Suite("iCloud: a regra de sincronização do mural")
struct SyncCoreTests {
    private static let boardName = "Casa 🏠"
    /// Um mural da própria pessoa: a zona é a mesma de `SyncFixtures.zone`, que dá o dono padrão.
    private static let cloud = BoardCloudInfo(
        database: .private, zoneName: SyncFixtures.zone.name, zoneOwnerName: SyncFixtures.zone.ownerName, permission: .owner)

    private static let imageFile = "AAAAAAAA-0000-4000-8000-000000000001.jpg"
    private static let attachmentFile = "AAAAAAAA-0000-4000-8000-000000000002.png"
    private static let videoFile = "AAAAAAAA-0000-4000-8000-000000000003.mov"
    private static let pdfFile = "AAAAAAAA-0000-4000-8000-000000000004.pdf"
    private static let newerFile = "BBBBBBBB-0000-4000-8000-000000000001.heic"

    /// O mural de exemplo com três cartões que preenchem tudo (lembrete, link e música), com as partes só de cada Mac. Ficam dentro da
    /// pasta do exemplo e sem lugar livre, para a estrutura ser válida: o conserto do `BoardMerge` não os mexe.
    private static func board() -> Board {
        var board = SyncFixtures.realisticBoard()
        let folder = board.items[0]
        for kind in [ItemKind.reminder, .link, .music] {
            var item = SyncFixtures.fullItem(kind: kind)
            item.parentID = folder.id
            item.folderPosition = nil
            board.items.append(item)
        }
        return board
    }

    // MARK: Ajudantes

    /// Um mural já enviado: o estado e o mural daqui coincidem e nada está pendente. Quem chama apaga `items`.
    private struct Scenario {
        var state: BoardSyncState
        var local: Board
        let items: URL
    }

    private func syncedScenario(board: Board = SyncCoreTests.board()) throws -> Scenario {
        let items = try makeItemsDirectory(files: [Self.imageFile, Self.attachmentFile, Self.pdfFile])
        var state = BoardSyncState(cloud: Self.cloud)
        try send(pending(state, board, items), from: board, state: &state, items: items)
        return Scenario(state: state, local: board, items: items)
    }

    /// Uma pasta `Items/` temporária com os arquivos dados.
    private func makeItemsDirectory(files: [String]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralSyncCore-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in files { try Data("conteúdo de \(file)".utf8).write(to: directory.appendingPathComponent(file)) }
        return directory
    }

    private func cleanUp(_ items: URL) {
        try? FileManager.default.removeItem(at: items.deletingLastPathComponent())
    }

    private func recordID(_ name: String) -> CloudRecordID {
        CloudRecordID(zone: SyncFixtures.zone, name: name)
    }

    private func cardID(_ item: BoardItem) -> CloudRecordID {
        recordID(item.id.uuidString)
    }

    private func saves(_ names: [String]) -> Set<PendingChange> {
        Set(names.map { PendingChange.save(recordID($0)) })
    }

    private func deletes(_ names: [String]) -> Set<PendingChange> {
        Set(names.map { PendingChange.delete(recordID($0)) })
    }

    /// Os nomes dos registros a gravar, ou, com `deleting`, a apagar.
    private func names(of changes: Set<PendingChange>, deleting: Bool = false) -> Set<String> {
        var result = Set<String>()
        for change in changes {
            switch change {
            case .save(let id) where !deleting: result.insert(id.name)
            case .delete(let id) where deleting: result.insert(id.name)
            default: break
            }
        }
        return result
    }

    private func pending(_ state: BoardSyncState, _ local: Board, _ items: URL, name: String = SyncCoreTests.boardName) -> Set<
        PendingChange
    > {
        SyncCore.pendingChanges(state: state, local: local, name: name, itemsDirectory: items)
    }

    private func record(_ id: CloudRecordID, _ scenario: Scenario) throws -> CloudRecord? {
        try SyncCore.record(
            for: id, state: scenario.state, local: scenario.local, name: Self.boardName, itemsDirectory: scenario.items)
    }

    /// O que o motor faz: monta o registro de cada gravação, o iCloud o aceita com uma marca de alteração nova e a base é atualizada.
    @discardableResult
    private func send(
        _ changes: Set<PendingChange>, from local: Board, state: inout BoardSyncState, items: URL, tag: String = "v1"
    ) throws -> [CloudRecord] {
        var saved: [CloudRecord] = []
        var deleted: [CloudRecordID] = []
        for change in changes {
            switch change {
            case .save(let id):
                var record = try #require(
                    try SyncCore.record(for: id, state: state, local: local, name: Self.boardName, itemsDirectory: items),
                    "o registro \(id.name) é pendente, mas não pôde ser montado")
                record.systemFields = Data("\(tag):\(id.name)".utf8)
                saved.append(record)
            case .delete(let id):
                deleted.append(id)
            }
        }
        try SyncCore.confirmSaved(saved, into: &state)
        SyncCore.confirmDeleted(deleted, into: &state)
        return saved
    }

    /// O registro de um cartão como o iCloud o devolveria, com a marca de alteração do servidor.
    private func serverCard(_ item: BoardItem, layer: Double, tag: String = "servidor") throws -> CloudRecord {
        var record = try SyncFixtures.cardRecord(item, layer: layer)
        record.systemFields = Data(tag.utf8)
        return record
    }

    /// O registro de um cartão gravado por um app mais novo: a versão do formato passa da que esta build lê.
    private func newerCard(_ item: BoardItem, layer: Double = 99) throws -> CloudRecord {
        var record = try serverCard(item, layer: layer, tag: "app-novo")
        record.fields["formatVersion"] = .int(Int64(Board.currentFormatVersion) + 1)
        return record
    }

    private func index(of kind: ItemKind, in board: Board) throws -> Int {
        try #require(board.items.firstIndex { $0.kind == kind })
    }

    // MARK: Mural recém-posto e ida e volta

    @Test("Mural recém-posto no iCloud: tudo é pendente, e da mídia só o que existe em Items/")
    func newBoardHasEverythingPending() throws {
        let local = Self.board()
        let items = try makeItemsDirectory(files: [Self.imageFile, Self.attachmentFile, Self.pdfFile])
        defer { cleanUp(items) }

        let result = pending(BoardSyncState(cloud: Self.cloud), local, items)

        var expected = saves(local.items.map(\.id.uuidString))
        expected.formUnion(saves(local.freeTexts.map(\.id.uuidString)))
        expected.formUnion(saves([CloudSchema.muralRecordName, Self.imageFile, Self.attachmentFile, Self.pdfFile]))
        #expect(result == expected)
        #expect(!result.contains(.save(recordID(Self.videoFile))), "o vídeo é citado, mas o arquivo não está em Items/")
    }

    @Test("Depois que o iCloud aceita os registros montados, nada fica pendente: ida e volta exata, sem eco")
    func acceptedRecordsLeaveNothingPending() throws {
        let local = Self.board()
        let items = try makeItemsDirectory(files: [Self.imageFile, Self.attachmentFile, Self.pdfFile])
        defer { cleanUp(items) }
        var state = BoardSyncState(cloud: Self.cloud)
        let first = pending(state, local, items)

        let sent = try send(first, from: local, state: &state, items: items)

        #expect(sent.count == first.count, "toda gravação pendente gerou um registro")
        #expect(pending(state, local, items).isEmpty)
        // A base tem exatamente o que foi enviado: os cartões na forma compartilhada, as datas bit a bit.
        #expect(Set(state.base.items) == Set(local.items.map(SharedFieldPolicy.shared)))
        #expect(state.base.freeTexts == local.freeTexts)
        let bits = { (items: [BoardItem]) in
            Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.createdAt.timeIntervalSinceReferenceDate.bitPattern) })
        }
        #expect(bits(state.base.items) == bits(local.items))
        #expect(state.base.formatVersion == local.requiredFormatVersion)
        #expect(state.baseName == Self.boardName && state.baseBoardFormatVersion == local.requiredFormatVersion)
        #expect(state.uploadedFiles == [Self.imageFile, Self.attachmentFile, Self.pdfFile])
        #expect(Set(state.mediaOwners.keys) == state.uploadedFiles)
        for file in state.uploadedFiles {
            let firstOwner = local.items.first { $0.assetFileNames.contains(file) }?.id
            #expect(state.mediaOwners[file] == firstOwner, "o dono é o primeiro cartão que cita \(file)")
        }
        #expect(Set(state.layers.keys) == Set(local.items.map(\.id)))
        #expect(Set(state.systemFields.keys) == names(of: first))
        #expect(state.systemFields["mural"] == Data("v1:mural".utf8))
    }

    @Test(
        "Datas com fração viajam sem diferença e não geram reenvio, no cartão, dentro do JSON e no texto livre",
        arguments: [779_123_456.123_456_789, 779_123_456.0.nextUp, 1.0e-7, -62_135_769_600.5])
    func fractionalDatesCauseNoResend(seconds: Double) throws {
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        let item = BoardItem(
            kind: .reminder, title: "Data", createdAt: date,
            reminder: ReminderSnapshot(identifier: "r", title: "t", dueDate: date, completionDate: date))
        let text = BoardFreeText(text: "Data", createdAt: date)
        let local = Board(items: [item], freeTexts: [text])
        let items = try makeItemsDirectory(files: [])
        defer { cleanUp(items) }
        var state = BoardSyncState(cloud: Self.cloud)

        try send(pending(state, local, items), from: local, state: &state, items: items)

        #expect(pending(state, local, items).isEmpty)
        let card = try #require(state.base.item(id: item.id))
        #expect(card.createdAt.timeIntervalSinceReferenceDate.bitPattern == seconds.bitPattern)
        #expect(card.reminder?.dueDate?.timeIntervalSinceReferenceDate.bitPattern == seconds.bitPattern)
        #expect(card.reminder?.completionDate?.timeIntervalSinceReferenceDate.bitPattern == seconds.bitPattern)
        #expect(state.base.freeText(id: text.id)?.createdAt.timeIntervalSinceReferenceDate.bitPattern == seconds.bitPattern)
    }

    @Test("O registro montado leva o tipo, os campos de agora e os campos de sistema que o iCloud deu")
    func recordsCarryTypeFieldsAndSystemFields() throws {
        let scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let state = scenario.state
        let sticky = scenario.local.items[try index(of: .sticky, in: scenario.local)]
        let freeText = try #require(scenario.local.freeTexts.first)
        let owner = try #require(scenario.local.items.first { $0.assetFileNames.contains(Self.imageFile) })

        let stickyLayer = try #require(state.layers[sticky.id])
        let card = try #require(try record(cardID(sticky), scenario))
        #expect(card.id == cardID(sticky) && card.type == "Card" && card.creatorUserRecordName == nil)
        #expect(card.fields == (try CardRecordMapping.fields(for: sticky, layer: stickyLayer)))
        #expect(card.systemFields == state.systemFields[sticky.id.uuidString])

        let text = try #require(try record(recordID(freeText.id.uuidString), scenario))
        #expect(text.type == "FreeText" && text.fields == CardRecordMapping.fields(for: freeText))

        let mural = try #require(try record(recordID("mural"), scenario))
        #expect(mural.type == "Mural" && mural.fields == CardRecordMapping.boardFields(name: Self.boardName, board: scenario.local))
        #expect(mural.systemFields == state.systemFields["mural"])

        let media = try #require(try record(recordID(Self.imageFile), scenario))
        #expect(media.type == "MediaFile" && media.systemFields == state.systemFields[Self.imageFile])
        #expect(
            media.fields == CardRecordMapping.mediaFields(fileURL: scenario.items.appendingPathComponent(Self.imageFile), cardID: owner.id))
    }

    // MARK: O que muda aqui

    @Test("Editar um campo deixa só aquele cartão pendente; o que dura é pendente até o iCloud aceitar")
    func editingOneFieldMakesOnlyThatCardPending() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let folder = try index(of: .folder, in: scenario.local)
        let note = try index(of: .text, in: scenario.local)

        scenario.local.items[folder].title = "Casa nova"
        #expect(pending(scenario.state, scenario.local, scenario.items) == saves([scenario.local.items[folder].id.uuidString]))

        scenario.local.items[note].position = BoardPoint(x: 1, y: 2)
        #expect(
            pending(scenario.state, scenario.local, scenario.items)
                == saves([scenario.local.items[folder].id.uuidString, scenario.local.items[note].id.uuidString]))

        try send(
            pending(scenario.state, scenario.local, scenario.items), from: scenario.local, state: &scenario.state, items: scenario.items)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
    }

    @Test("Mudar só as partes locais (frases curtas, prévia do link, capa da música) não deixa nada pendente")
    func localOnlyPartsLeaveNothingPending() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let note = try index(of: .text, in: scenario.local)
        let link = try index(of: .link, in: scenario.local)
        let music = try index(of: .music, in: scenario.local)

        scenario.local.items[note].keySentences = KeySentenceRecord(source: "Texto da nota com 2 linhas", choices: [:])
        scenario.local.items[link].link?.previewImageFile = "outra-previa.jpg"
        scenario.local.items[link].link?.iconFile = "outro-icone.png"
        scenario.local.items[link].link?.preview = .ready(fetchedAt: SyncFixtures.thirdFractionalDate)
        scenario.local.items[music].music?.artworkFile = "outra-capa.jpg"
        scenario.local.items[music].music?.libraryID = "OUTRO-ID"

        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
    }

    @Test("Uma mudança feita durante o envio continua pendente, porque a base só tem o que o iCloud aceitou")
    func changeDuringUploadStaysPending() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let folder = try index(of: .folder, in: scenario.local)
        let id = cardID(scenario.local.items[folder])
        scenario.local.items[folder].title = "Primeira edição"
        var sent = try #require(try record(id, scenario))
        sent.systemFields = Data("v2".utf8)

        scenario.local.items[folder].title = "Segunda edição, durante o envio"
        try SyncCore.confirmSaved([sent], into: &scenario.state)

        #expect(scenario.state.base.item(id: scenario.local.items[folder].id)?.title == "Primeira edição", "a base tem o que foi enviado")
        #expect(pending(scenario.state, scenario.local, scenario.items) == [.save(id)])
        #expect(scenario.state.systemFields[id.name] == Data("v2".utf8))
    }

    @Test("Cartão levado ao topo deixa só ele pendente, pelo número de empilhamento, e o número vai no registro")
    func raisedCardIsTheOnlyOnePending() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let top = (scenario.state.layers.values.max() ?? 0) + 1

        for position in [0, 5] {
            let moved = scenario.local.items.remove(at: position)
            scenario.local.items.append(moved)
            let id = cardID(moved)

            #expect(pending(scenario.state, scenario.local, scenario.items) == [.save(id)])
            let sent = try #require(try record(id, scenario))
            #expect(sent.fields["layer"] == .double(scenario.state.layers.values.max()! + 1))

            try send(
                pending(scenario.state, scenario.local, scenario.items), from: scenario.local, state: &scenario.state, items: scenario.items
            )
            #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
            #expect(scenario.state.layers[moved.id] == scenario.state.layers.values.max())
        }
        #expect(scenario.state.layers.values.max() == top + 1)
    }

    @Test("Texto livre: editar deixa só ele pendente, e apagar pede para apagar o registro dele")
    func freeTextEditAndRemoval() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let id = try #require(scenario.local.freeTexts.first).id.uuidString

        scenario.local.freeTexts[0] = BoardFreeText(
            id: scenario.local.freeTexts[0].id, text: "Oi de novo", position: BoardPoint(x: 9, y: 9), createdAt: SyncFixtures.fractionalDate
        )
        #expect(pending(scenario.state, scenario.local, scenario.items) == saves([id]))
        try send(
            pending(scenario.state, scenario.local, scenario.items), from: scenario.local, state: &scenario.state, items: scenario.items)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)

        scenario.local.freeTexts.removeAll()
        // O mural continua exigindo a versão 10 por causa dos outros cartões, então só o texto livre é apagado.
        #expect(pending(scenario.state, scenario.local, scenario.items) == deletes([id]))
        try send(
            pending(scenario.state, scenario.local, scenario.items), from: scenario.local, state: &scenario.state, items: scenario.items)
        #expect(scenario.state.base.freeTexts.isEmpty && scenario.state.systemFields[id] == nil)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
    }

    // MARK: O registro do mural

    @Test("Renomear o mural, ou nunca o ter enviado, deixa só o registro do mural pendente")
    func boardRecordNameChanges() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }

        #expect(pending(scenario.state, scenario.local, scenario.items, name: "Outro nome") == saves(["mural"]))

        scenario.state.baseName = nil
        #expect(pending(scenario.state, scenario.local, scenario.items) == saves(["mural"]))
    }

    @Test("O primeiro cartão que exige um formato mais novo deixa também o registro do mural pendente, com a versão nova")
    func raisedFormatVersionMakesBoardPending() throws {
        let sticky = BoardItem(kind: .sticky, title: "Tinta", text: "Azul")
        var scenario = try syncedScenario(board: Board(items: [sticky]))
        defer { cleanUp(scenario.items) }
        #expect(scenario.state.base.requiredFormatVersion == 1)

        let link = BoardItem(
            kind: .link, title: "Site",
            link: LinkInfo(url: URL(string: "https://example.com/a")!, pageTitle: "Página", siteName: "Exemplo", summary: "Resumo"))
        scenario.local.items.append(link)

        #expect(pending(scenario.state, scenario.local, scenario.items) == saves([link.id.uuidString, "mural"]))
        let mural = try #require(try record(recordID("mural"), scenario))
        #expect(CardRecordMapping.boardFormatVersion(from: mural) == 3)
        try send(
            pending(scenario.state, scenario.local, scenario.items), from: scenario.local, state: &scenario.state, items: scenario.items)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
    }

    @Test("Cartão que sobe a versão do formato aceito sem o registro do mural: o mural continua pendente até ser aceito")
    func boardStaysPendingWhenOnlyTheCardIsAccepted() throws {
        var scenario = try syncedScenario(board: Board(items: [BoardItem(kind: .sticky, title: "Tinta", text: "Azul")]))
        defer { cleanUp(scenario.items) }
        #expect(scenario.state.baseBoardFormatVersion == 1)
        let link = BoardItem(
            kind: .link, title: "Site",
            link: LinkInfo(url: URL(string: "https://example.com/a")!, pageTitle: "Página", siteName: "Exemplo", summary: "Resumo"))
        scenario.local.items.append(link)
        var linkRecord = try #require(try record(cardID(link), scenario))
        linkRecord.systemFields = Data("v2".utf8)

        try SyncCore.confirmSaved([linkRecord], into: &scenario.state)

        #expect(scenario.state.base.requiredFormatVersion == 3, "a base já exige a versão 3")
        #expect(scenario.state.baseBoardFormatVersion == 1, "o registro do mural no iCloud segue na 1")
        #expect(pending(scenario.state, scenario.local, scenario.items) == saves(["mural"]))

        var mural = try #require(try record(recordID("mural"), scenario))
        mural.systemFields = Data("v2".utf8)
        try SyncCore.confirmSaved([mural], into: &scenario.state)
        #expect(scenario.state.baseBoardFormatVersion == 3)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
    }

    @Test("Apagado o registro do mural no iCloud, o nome e a versão voltam a ser pendentes e o mural é regravado")
    func deletedBoardRecordIsPendingAgain() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        #expect(scenario.state.baseName == Self.boardName && scenario.state.baseBoardFormatVersion == 11)

        let received = try SyncCore.receive(saved: [], deleted: [recordID("mural")], into: &scenario.state)

        #expect(received.isEmpty && received.name == nil)
        #expect(scenario.state.baseName == nil && scenario.state.baseBoardFormatVersion == nil)
        #expect(scenario.state.systemFields["mural"] == nil)
        #expect(pending(scenario.state, scenario.local, scenario.items) == saves(["mural"]))
    }

    @Test("Mural gravado por um app mais novo: a versão fica guardada e o registro do mural não é regravado")
    func boardFromNewerAppIsNotRewritten() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        var mural = SyncFixtures.record(
            .mural, name: "mural",
            fields: ["name": .string("Nome do app novo"), "formatVersion": .int(Int64(Board.currentFormatVersion) + 1)])
        mural.systemFields = Data("app-novo".utf8)

        let received = try SyncCore.receive(saved: [mural], deleted: [], into: &scenario.state)

        #expect(received.name == "Nome do app novo" && scenario.state.baseBoardFormatVersion == Board.currentFormatVersion + 1)
        let edited = scenario.local.items[0].id
        scenario.local.items[0].title = "Editado aqui"
        let changes = pending(scenario.state, scenario.local, scenario.items, name: "Outro nome")
        #expect(changes == saves([edited.uuidString]), "os cartões seguem, o mural não")
        #expect(try record(recordID("mural"), scenario) == nil)
    }

    // MARK: Apagar

    @Test("Cartão apagado: apaga o registro dele e a mídia que só ele citava, não a que outro cartão ainda cita")
    func deletedCardReleasesOnlyItsOwnMedia() throws {
        let alone = BoardItem(kind: .image, title: "Só eu", fileName: Self.imageFile)
        let first = BoardItem(kind: .image, title: "Junto 1", fileName: Self.attachmentFile)
        let second = BoardItem(kind: .image, title: "Junto 2", fileName: Self.attachmentFile)
        let keeper = BoardItem(kind: .sticky, title: "Fica", text: "x")
        var scenario = try syncedScenario(board: Board(items: [alone, first, second, keeper]))
        defer { cleanUp(scenario.items) }
        #expect(scenario.state.uploadedFiles == [Self.imageFile, Self.attachmentFile])

        scenario.local.items.removeAll { $0.id == alone.id || $0.id == first.id }

        #expect(
            pending(scenario.state, scenario.local, scenario.items)
                == deletes([alone.id.uuidString, first.id.uuidString, Self.imageFile]),
            "o arquivo que o segundo cartão ainda cita não sai")

        scenario.local.items.removeAll { $0.id == second.id }
        #expect(
            pending(scenario.state, scenario.local, scenario.items)
                == deletes([alone.id.uuidString, first.id.uuidString, second.id.uuidString, Self.imageFile, Self.attachmentFile]))
    }

    @Test(
        "Mídia de um cartão de app mais novo nunca sai, chegue o arquivo antes ou depois do registro do cartão",
        arguments: [false, true])
    func newerAppMediaIsNeverDeleted(mediaFirst: Bool) throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let owner = BoardItem(kind: .image, title: "Do app novo", fileName: Self.newerFile)
        let newer = try newerCard(owner)
        let media = SyncFixtures.record(
            .mediaFile, name: Self.newerFile,
            fields: CardRecordMapping.mediaFields(
                fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(Self.newerFile), cardID: owner.id))
        scenario.local.items = []
        scenario.local.freeTexts = []
        let deletedNames = { names(of: pending(scenario.state, scenario.local, scenario.items), deleting: true) }

        for record in mediaFirst ? [media, newer] : [newer, media] {
            _ = try SyncCore.receive(saved: [record], deleted: [], into: &scenario.state)
            #expect(!deletedNames().contains(Self.newerFile), "nem no meio do caminho")
        }

        #expect(scenario.state.uploadedFiles.contains(Self.newerFile))
        #expect(scenario.state.unsupportedRecordNames == [owner.id.uuidString])
        let known = scenario.state.base.items.map(\.id.uuidString) + scenario.state.base.freeTexts.map(\.id.uuidString)
        #expect(
            deletedNames() == Set(known + [Self.imageFile, Self.attachmentFile, Self.pdfFile]), "sai o que este Mac conhecia, e só isso")
        #expect(!deletedNames().contains(owner.id.uuidString))
    }

    @Test("Cartão apagado aceito antes do arquivo: apagar o arquivo continua pendente, até ele sair")
    func fileDeletionSurvivesTheCardBeingConfirmedFirst() throws {
        let alone = BoardItem(kind: .image, title: "Só eu", fileName: Self.imageFile)
        let keeper = BoardItem(kind: .sticky, title: "Fica", text: "x")
        var scenario = try syncedScenario(board: Board(items: [alone, keeper]))
        defer { cleanUp(scenario.items) }
        #expect(scenario.state.mediaOwners == [Self.imageFile: alone.id])
        scenario.local.items.removeAll { $0.id == alone.id }
        #expect(pending(scenario.state, scenario.local, scenario.items) == deletes([alone.id.uuidString, Self.imageFile]))

        SyncCore.confirmDeleted([cardID(alone)], into: &scenario.state)

        #expect(scenario.state.base.item(id: alone.id) == nil)
        #expect(
            pending(scenario.state, scenario.local, scenario.items) == deletes([Self.imageFile]),
            "o cartão já saiu da base, mas o arquivo dele continua pendente")
        SyncCore.confirmDeleted([recordID(Self.imageFile)], into: &scenario.state)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
        #expect(scenario.state.uploadedFiles.isEmpty && scenario.state.mediaOwners.isEmpty)
    }

    @Test("Arquivo que chega antes do seu cartão não é apagado; com o cartão aqui, apagá-lo também apaga o arquivo")
    func mediaArrivingBeforeItsCardIsKept() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let arrived = "CCCCCCCC-0000-4000-8000-000000000009.png"
        let card = BoardItem(kind: .image, title: "Da Ana", fileName: arrived)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("download.tmp")
        let media = SyncFixtures.record(.mediaFile, name: arrived, fields: CardRecordMapping.mediaFields(fileURL: url, cardID: card.id))
        let top = (scenario.state.layers.values.max() ?? 0) + 1

        _ = try SyncCore.receive(saved: [media], deleted: [], into: &scenario.state)

        #expect(scenario.state.uploadedFiles.contains(arrived) && scenario.state.mediaOwners[arrived] == nil, "o cartão dele não chegou")
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty, "arquivo sem cartão ainda não é de cartão apagado")

        let received = try SyncCore.receive(saved: [try serverCard(card, layer: top)], deleted: [], into: &scenario.state)
        scenario.local = BoardMerge.apply(received.changes, to: scenario.local, base: received.previousBase).board

        #expect(scenario.state.mediaOwners[arrived] == card.id, "com o cartão aqui, o arquivo ganha dono")
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
        scenario.local.items.removeAll { $0.id == card.id }
        #expect(pending(scenario.state, scenario.local, scenario.items) == deletes([card.id.uuidString, arrived]))
        SyncCore.confirmDeleted([cardID(card)], into: &scenario.state)
        #expect(pending(scenario.state, scenario.local, scenario.items) == deletes([arrived]))
    }

    @Test("Arquivo aceito sem o cartão (lote partido): se o cartão sumir antes de subir, o arquivo ainda sai")
    func fileAcceptedWithoutItsCardStillLeavesWhenTheCardVanishes() throws {
        let card = BoardItem(kind: .image, title: "Foto", fileName: Self.imageFile)
        var local = Board(items: [card])
        let items = try makeItemsDirectory(files: [Self.imageFile])
        defer { cleanUp(items) }
        var state = BoardSyncState(cloud: Self.cloud)
        var media = try #require(
            try SyncCore.record(for: recordID(Self.imageFile), state: state, local: local, name: Self.boardName, itemsDirectory: items))
        media.systemFields = Data("v1".utf8)

        try SyncCore.confirmSaved([media], into: &state)
        local.items.removeAll()

        #expect(state.base.items.isEmpty && state.mediaOwners == [Self.imageFile: card.id])
        #expect(names(of: pending(state, local, items), deleting: true) == [Self.imageFile])
    }

    @Test("Estado sem donos de arquivo (gravado antes deles): vale a regra de um cartão da base citar o arquivo")
    func stateWithoutOwnersFallsBackToTheBase() throws {
        let alone = BoardItem(kind: .image, title: "Só eu", fileName: Self.imageFile)
        let keeper = BoardItem(kind: .sticky, title: "Fica", text: "x")
        var scenario = try syncedScenario(board: Board(items: [alone, keeper]))
        defer { cleanUp(scenario.items) }
        scenario.state.mediaOwners = [:]
        scenario.state.uploadedFiles.insert(Self.newerFile)
        scenario.local.items.removeAll { $0.id == alone.id }

        #expect(pending(scenario.state, scenario.local, scenario.items) == deletes([alone.id.uuidString, Self.imageFile]))
        SyncCore.confirmDeleted([cardID(alone)], into: &scenario.state)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty, "sem dono e sem cartão da base que o cite, fica")
    }

    @Test("Depois que o iCloud apaga, o que o nome representava sai da base, dos números, dos arquivos enviados e dos campos de sistema")
    func confirmDeletedForgetsEverything() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let image = scenario.local.items[try index(of: .image, in: scenario.local)]
        let pdf = scenario.local.items[try index(of: .pdf, in: scenario.local)]
        let freeText = try #require(scenario.local.freeTexts.first)
        scenario.local.items.removeAll { $0.id == image.id || $0.id == pdf.id }
        scenario.local.freeTexts.removeAll()

        let changes = pending(scenario.state, scenario.local, scenario.items)
        // Outros cartões ainda citam o arquivo da imagem; o do PDF só ele citava.
        #expect(changes == deletes([image.id.uuidString, pdf.id.uuidString, freeText.id.uuidString, Self.pdfFile]))
        SyncCore.confirmDeleted(
            [cardID(image), cardID(pdf), recordID(freeText.id.uuidString), recordID(Self.pdfFile), recordID("desconhecido")],
            into: &scenario.state)

        #expect(scenario.state.base.item(id: image.id) == nil && scenario.state.base.item(id: pdf.id) == nil)
        #expect(scenario.state.base.freeTexts.isEmpty)
        #expect(scenario.state.layers[image.id] == nil && scenario.state.layers[pdf.id] == nil)
        #expect(scenario.state.uploadedFiles == [Self.imageFile, Self.attachmentFile])
        for name in [image.id.uuidString, pdf.id.uuidString, freeText.id.uuidString, Self.pdfFile] {
            #expect(scenario.state.systemFields[name] == nil)
        }
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
    }

    // MARK: Mídia

    @Test("Mídia: o arquivo só sobe quando existe em Items/, e quem decide se existe é o fileExists recebido")
    func mediaWaitsForTheFile() throws {
        let card = BoardItem(kind: .image, title: "Foto", fileName: Self.imageFile)
        let local = Board(items: [card])
        let items = try makeItemsDirectory(files: [])
        defer { cleanUp(items) }
        var state = BoardSyncState(cloud: Self.cloud)
        try send(pending(state, local, items), from: local, state: &state, items: items)
        #expect(pending(state, local, items).isEmpty && state.uploadedFiles.isEmpty)
        #expect(
            try SyncCore.record(for: recordID(Self.imageFile), state: state, local: local, name: Self.boardName, itemsDirectory: items)
                == nil)

        try Data("pixels".utf8).write(to: items.appendingPathComponent(Self.imageFile))

        #expect(pending(state, local, items) == saves([Self.imageFile]))
        let denied = SyncCore.pendingChanges(
            state: state, local: local, name: Self.boardName, itemsDirectory: items, fileExists: { _ in false })
        #expect(denied.isEmpty, "o fileExists recebido manda")
        try send(pending(state, local, items), from: local, state: &state, items: items)
        #expect(state.uploadedFiles == [Self.imageFile] && pending(state, local, items).isEmpty)
    }

    @Test("Nome de arquivo que sairia de Items/ nunca sobe, nem com o arquivo existindo")
    func unsafeFileNameNeverLeaves() throws {
        let items = try makeItemsDirectory(files: [])
        defer { cleanUp(items) }
        try Data("segredo".utf8).write(to: items.deletingLastPathComponent().appendingPathComponent("segredo.txt"))
        let card = BoardItem(kind: .image, title: "Mau", fileName: "../segredo.txt")
        let local = Board(items: [card])
        let state = BoardSyncState(cloud: Self.cloud)

        #expect(pending(state, local, items) == saves([card.id.uuidString, "mural"]))
        #expect(
            try SyncCore.record(for: recordID("../segredo.txt"), state: state, local: local, name: Self.boardName, itemsDirectory: items)
                == nil)
    }

    // MARK: Registro de app mais novo

    @Test("Registro de app mais novo: vai para os não suportados, nunca é regravado nem apagado e sai de lá quando apagado no iCloud")
    func newerAppRecordIsLeftAlone() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let position = try index(of: .sticky, in: scenario.local)
        let target = scenario.local.items[position]
        let name = target.id.uuidString
        let baseBefore = scenario.state.base
        let layerBefore = scenario.state.layers[target.id]

        let received = try SyncCore.receive(saved: [try newerCard(target)], deleted: [], into: &scenario.state)

        #expect(scenario.state.unsupportedRecordNames == [name])
        #expect(received.isEmpty && received.skippedRecordNames.isEmpty)
        #expect(scenario.state.base == baseBefore && scenario.state.layers[target.id] == layerBefore, "a base não muda")
        #expect(scenario.state.systemFields[name] == Data("app-novo".utf8))

        scenario.local.items[position].title = "Editado aqui"
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty, "não regrava")
        #expect(try record(cardID(target), scenario) == nil)
        scenario.local.items.remove(at: position)
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty, "não apaga")

        let gone = try SyncCore.receive(saved: [], deleted: [cardID(target)], into: &scenario.state)
        #expect(scenario.state.unsupportedRecordNames.isEmpty && scenario.state.systemFields[name] == nil)
        #expect(gone.changes.deletedItemIDs == [target.id], "apagado por outra pessoa, o cartão que este Mac tinha sai")
    }

    @Test("Registro de app mais novo que este Mac nunca viu também só fica anotado, e um que volta a ser entendido sai da lista")
    func unknownNewerRecordIsOnlyNoted() throws {
        var state = BoardSyncState(cloud: Self.cloud)
        let item = BoardItem(kind: .sticky, title: "Tinta", text: "Azul")
        var hologram = try serverCard(item, layer: 1)
        hologram.fields["kind"] = .string("hologram")

        let received = try SyncCore.receive(saved: [hologram], deleted: [], into: &state)

        #expect(received.isEmpty && state.unsupportedRecordNames == [item.id.uuidString] && state.base == Board())

        let understood = try SyncCore.receive(saved: [try serverCard(item, layer: 2)], deleted: [], into: &state)
        #expect(state.unsupportedRecordNames.isEmpty && state.base.item(id: item.id) == item && state.layers[item.id] == 2)
        #expect(understood.changes.savedItems == [item])
    }

    @Test("Texto livre de app mais novo também só fica anotado: não entra no mural e não sobe nem é apagado")
    func newerFreeTextIsOnlyNoted() throws {
        var state = BoardSyncState(cloud: Self.cloud)
        let freeText = BoardFreeText(text: "Do futuro", position: BoardPoint(x: 10, y: 20), createdAt: SyncFixtures.fractionalDate)
        var fields = CardRecordMapping.fields(for: freeText)
        fields["formatVersion"] = .int(Int64(Board.currentFormatVersion + 1))
        var future = SyncFixtures.record(.freeText, name: freeText.id.uuidString, fields: fields)
        future.systemFields = Data("app-novo".utf8)

        let received = try SyncCore.receive(saved: [future], deleted: [], into: &state)

        #expect(received.isEmpty && state.unsupportedRecordNames == [freeText.id.uuidString] && state.base == Board())
        // Um texto com o mesmo id aqui não sobe por cima do registro do app mais novo.
        let local = Board(freeTexts: [freeText])
        let changes = SyncCore.pendingChanges(
            state: state, local: local, name: Self.boardName, itemsDirectory: URL(filePath: "/nao-existe"))
        #expect(!changes.contains(.save(recordID(freeText.id.uuidString))))
        #expect(!changes.contains(.delete(recordID(freeText.id.uuidString))))
    }

    @Test("O nome que chegou vale se o daqui ainda é o da base; renomeado aqui, fica o daqui; sem base, vale o que chegou")
    func mergedNameFollowsTheSimpleFieldRule() {
        let arrived = ReceivedChanges(name: "Nome de lá", previousBaseName: "Casa")
        #expect(arrived.mergedName(local: "Casa") == "Nome de lá")
        #expect(arrived.mergedName(local: "Nome daqui") == "Nome daqui")
        #expect(ReceivedChanges(name: "Nome de lá").mergedName(local: "Qualquer") == "Nome de lá")
        #expect(ReceivedChanges(previousBaseName: "Casa").mergedName(local: "Nome daqui") == "Nome daqui", "sem nome novo, nada muda")
    }

    // MARK: O que chegou

    @Test("Cartões gravados e apagados por outra pessoa entram na base, e juntados ao mural não voltam ao iCloud")
    func receivedChangesAreMergedWithoutEcho() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let before = scenario.state
        var edited = SharedFieldPolicy.shared(scenario.local.items[try index(of: .sticky, in: scenario.local)])
        edited.title = "Editado por Ana"
        edited.text = "Tinta verde"
        let created = BoardItem(kind: .sticky, title: "Chegou", createdAt: SyncFixtures.otherFractionalDate, text: "Chegou")
        let removed = scenario.local.items[try index(of: .checklist, in: scenario.local)]
        let top = (before.layers.values.max() ?? 0) + 1
        let records = [
            try serverCard(edited, layer: try #require(before.layers[edited.id]), tag: "ana-1"),
            try serverCard(created, layer: top, tag: "ana-2"),
        ]

        let received = try SyncCore.receive(saved: records, deleted: [cardID(removed)], into: &scenario.state)

        #expect(received.previousBase == before.base)
        #expect(received.changes.savedItems == [edited, created])
        #expect(received.changes.deletedItemIDs == [removed.id])
        #expect(received.changes.layers == scenario.state.layers)
        #expect(received.changes.layers[created.id] == top && received.changes.layers[removed.id] == nil)
        #expect(received.name == nil && received.files.isEmpty && received.skippedRecordNames.isEmpty && !received.isEmpty)
        #expect(scenario.state.base.item(id: edited.id) == edited && scenario.state.base.item(id: created.id) == created)
        #expect(scenario.state.base.item(id: removed.id) == nil)
        #expect(scenario.state.systemFields[edited.id.uuidString] == Data("ana-1".utf8))
        #expect(scenario.state.systemFields[created.id.uuidString] == Data("ana-2".utf8))
        #expect(scenario.state.systemFields[removed.id.uuidString] == nil)
        #expect(scenario.state.base.formatVersion == scenario.state.base.requiredFormatVersion)

        let merged = BoardMerge.apply(received.changes, to: scenario.local, base: received.previousBase)
        #expect(merged.conflictCopies.isEmpty)
        #expect(merged.board.item(id: created.id) == created && merged.board.item(id: removed.id) == nil)
        #expect(merged.board.item(id: edited.id)?.title == "Editado por Ana" && merged.board.items.last?.id == created.id)
        scenario.local = merged.board
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty, "o que chegou e foi juntado não volta ao iCloud")
    }

    @Test("O próprio envio buscado de volta (eco do iCloud) não muda o mural nem gera envio")
    func echoOfOwnUploadChangesNothing() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        var echo = try scenario.local.items.map { try serverCard($0, layer: try #require(scenario.state.layers[$0.id])) }
        echo.append(try #require(try record(recordID("mural"), scenario)))
        echo.append(try #require(try record(recordID(scenario.local.freeTexts[0].id.uuidString), scenario)))

        let received = try SyncCore.receive(saved: echo, deleted: [], into: &scenario.state)
        let merged = BoardMerge.apply(received.changes, to: scenario.local, base: received.previousBase)

        #expect(merged.conflictCopies.isEmpty && merged.repairedItemIDs.isEmpty)
        #expect(merged.board.items.map(SharedFieldPolicy.shared) == scenario.local.items.map(SharedFieldPolicy.shared))
        #expect(merged.board.freeTexts == scenario.local.freeTexts)
        scenario.local = merged.board
        #expect(pending(scenario.state, scenario.local, scenario.items).isEmpty)
    }

    @Test("Conflito: a versão do servidor entra na base, e o que esta pessoa mudou aqui continua pendente depois da junção")
    func conflictKeepsLocalChangePending() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let position = try index(of: .folder, in: scenario.local)
        let original = scenario.local.items[position]
        scenario.local.items[position].title = "Casa nova"
        var theirs = SharedFieldPolicy.shared(original)
        theirs.tag = "CASA 2"
        let server = try serverCard(theirs, layer: try #require(scenario.state.layers[original.id]), tag: "servidor-2")

        let received = try SyncCore.receive(saved: [server], deleted: [], into: &scenario.state)
        let merged = BoardMerge.apply(received.changes, to: scenario.local, base: received.previousBase)
        scenario.local = merged.board

        #expect(scenario.state.base.item(id: original.id) == theirs, "a base passa a ser a versão do servidor")
        let item = try #require(merged.board.item(id: original.id))
        #expect(item.title == "Casa nova" && item.tag == "CASA 2" && merged.conflictCopies.isEmpty)
        #expect(pending(scenario.state, scenario.local, scenario.items) == [.save(cardID(original))], "o local junto difere da base nova")
        let retry = try #require(try record(cardID(original), scenario))
        #expect(retry.systemFields == Data("servidor-2".utf8), "a nova gravação leva a marca de alteração do servidor")
        #expect(retry.fields["title"] == .string("Casa nova") && retry.fields["tag"] == .string("CASA 2"))
    }

    @Test("Texto livre, nome do mural e arquivo de mídia que chegam entram no estado e no resultado; apagados saem")
    func receivedFreeTextBoardAndMedia() throws {
        var state = BoardSyncState(cloud: Self.cloud)
        let freeText = BoardFreeText(text: "Chegou", position: BoardPoint(x: 3, y: 4), createdAt: SyncFixtures.fractionalDate)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("download.tmp")
        var textRecord = SyncFixtures.record(.freeText, name: freeText.id.uuidString, fields: CardRecordMapping.fields(for: freeText))
        textRecord.systemFields = Data("t".utf8)
        let boardRecord = SyncFixtures.record(
            .mural, name: "mural", fields: CardRecordMapping.boardFields(name: "Nome novo", board: Board(freeTexts: [freeText])))
        let mediaRecord = SyncFixtures.record(
            .mediaFile, name: Self.imageFile, fields: CardRecordMapping.mediaFields(fileURL: url, cardID: UUID()))

        let received = try SyncCore.receive(saved: [textRecord, boardRecord, mediaRecord], deleted: [], into: &state)

        #expect(received.changes.savedFreeTexts == [freeText] && received.name == "Nome novo" && received.files == [Self.imageFile: url])
        #expect(state.base.freeTexts == [freeText] && state.baseName == "Nome novo" && state.uploadedFiles == [Self.imageFile])
        #expect(state.baseBoardFormatVersion == 7, "a versão que o registro do mural declara")
        #expect(state.mediaOwners.isEmpty, "o cartão dono do arquivo não chegou")
        #expect(state.systemFields[freeText.id.uuidString] == Data("t".utf8) && !received.isEmpty)

        let removed = try SyncCore.receive(
            saved: [], deleted: [recordID(freeText.id.uuidString), recordID(Self.imageFile), recordID("desconhecido")], into: &state)
        #expect(removed.changes.deletedFreeTextIDs == [freeText.id] && removed.changes.deletedItemIDs.isEmpty)
        #expect(state.base.freeTexts.isEmpty && state.uploadedFiles.isEmpty)
        #expect(state.systemFields[freeText.id.uuidString] == nil && state.baseName == "Nome novo")

        let unknown = try SyncCore.receive(saved: [], deleted: [recordID("outro"), recordID(UUID().uuidString)], into: &state)
        #expect(unknown.isEmpty, "nome desconhecido é ignorado")
    }

    @Test("Gravado e apagado na mesma leva: vale o apagado")
    func deletedWinsOverSavedInTheSameBatch() throws {
        var state = BoardSyncState(cloud: Self.cloud)
        let item = BoardItem(kind: .sticky, title: "Efêmero", text: "x")

        let received = try SyncCore.receive(saved: [try serverCard(item, layer: 1)], deleted: [cardID(item)], into: &state)

        #expect(received.changes.deletedItemIDs == [item.id] && received.changes.savedItems.isEmpty)
        #expect(state.base.items.isEmpty && state.layers.isEmpty && state.systemFields.isEmpty)
    }

    @Test("Registro ilegível na leva é ignorado e o nome vai para os ignorados; o resto entra")
    func unreadableRecordsAreSkipped() throws {
        var state = BoardSyncState(cloud: Self.cloud)
        let good = BoardItem(kind: .sticky, title: "Bom", text: "x")
        let goodText = BoardFreeText(text: "Bom", createdAt: SyncFixtures.fractionalDate)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("download.tmp")
        let unreadable = [
            SyncFixtures.record(.card, name: UUID().uuidString, fields: ["kind": .string("sticky")]),
            SyncFixtures.record(.freeText, name: UUID().uuidString, fields: ["text": .string("sem posição")]),
            SyncFixtures.record(.mural, name: "mural", fields: ["formatVersion": .int(1)]),
            SyncFixtures.record(.mediaFile, name: "../fora.png", fields: ["file": .asset(url)]),
            CloudRecord(id: recordID("tipo-novo"), type: "Comentario", fields: [:], systemFields: Data("x".utf8)),
        ]
        var records = [try serverCard(good, layer: 1)]
        records += unreadable.prefix(2)
        records.append(SyncFixtures.record(.freeText, name: goodText.id.uuidString, fields: CardRecordMapping.fields(for: goodText)))
        records += unreadable.dropFirst(2)

        let received = try SyncCore.receive(saved: records, deleted: [], into: &state)

        #expect(received.skippedRecordNames == unreadable.map(\.id.name))
        #expect(received.changes.savedItems == [good] && received.changes.savedFreeTexts == [goodText])
        #expect(state.base.items == [good] && state.base.freeTexts == [goodText])
        #expect(state.baseName == nil && state.uploadedFiles.isEmpty && received.name == nil && received.files.isEmpty)
        #expect(state.systemFields["tipo-novo"] == nil, "o registro ignorado não deixa nada no estado")
    }

    @Test("Confirmar registros é tudo ou nada: um registro ilegível no meio deixa o estado como estava")
    func confirmSavedIsAllOrNothing() throws {
        var state = BoardSyncState(cloud: Self.cloud)
        let good = BoardItem(kind: .sticky, title: "Bom", text: "x")
        let broken = SyncFixtures.record(.card, name: UUID().uuidString, fields: ["kind": .string("sticky")])

        let records = [try serverCard(good, layer: 1), broken]
        var thrown: (any Error)?
        do {
            try SyncCore.confirmSaved(records, into: &state)
        } catch {
            thrown = error
        }

        #expect(thrown is CardRecordMappingError)
        #expect(state == BoardSyncState(cloud: Self.cloud))
    }

    // MARK: Montar o registro

    @Test("Montar o registro de algo que não existe mais aqui dá nil, e a mudança some")
    func recordOfSomethingGoneIsNil() throws {
        var scenario = try syncedScenario()
        defer { cleanUp(scenario.items) }
        let card = scenario.local.items[try index(of: .sticky, in: scenario.local)]
        let freeText = try #require(scenario.local.freeTexts.first)
        try Data("sem dono".utf8).write(to: scenario.items.appendingPathComponent("CCCCCCCC-0000-4000-8000-000000000001.png"))
        scenario.local.items.removeAll { $0.id == card.id }
        scenario.local.freeTexts.removeAll()

        #expect(try record(cardID(card), scenario) == nil)
        #expect(try record(recordID(freeText.id.uuidString), scenario) == nil)
        #expect(try record(recordID(Self.videoFile), scenario) == nil, "citado por um cartão, mas o arquivo não está em Items/")
        #expect(try record(recordID("CCCCCCCC-0000-4000-8000-000000000001.png"), scenario) == nil, "no disco, mas nenhum cartão o cita")
        #expect(try record(recordID("desconhecido"), scenario) == nil)
        #expect(try record(recordID(card.id.uuidString.lowercased()), scenario) == nil, "só o uuidString canônico é nome de registro")
        #expect(try record(recordID("mural"), scenario) != nil, "o mural sempre existe")
    }

    @Test("A versão do formato que o registro do mural declara volta como foi gravada")
    func boardFormatVersionRoundTrips() {
        let link = BoardItem(
            kind: .link, title: "Site",
            link: LinkInfo(url: URL(string: "https://example.com")!, pageTitle: "P", siteName: "S", summary: "R", remoteImageURL: nil))
        let boards: [(board: Board, version: Int)] = [
            (Board(), 1),
            (Board(items: [link]), 3),
            (Board(freeTexts: [BoardFreeText(text: "Oi")]), 7),
            (Self.board(), 11),
        ]
        for (board, version) in boards {
            let record = SyncFixtures.record(.mural, name: "mural", fields: CardRecordMapping.boardFields(name: "Casa", board: board))
            #expect(CardRecordMapping.boardFormatVersion(from: record) == version)
            #expect(board.requiredFormatVersion == version)
        }
    }

    @Test("Sem versão legível, ou em registro que não é do mural, não há versão do formato")
    func boardFormatVersionNeedsAMuralRecordWithAnInteger() {
        let newer = Int64(Board.currentFormatVersion) + 1
        #expect(CardRecordMapping.boardFormatVersion(from: SyncFixtures.record(.mural, name: "mural", fields: [:])) == nil)
        #expect(
            CardRecordMapping.boardFormatVersion(from: SyncFixtures.record(.mural, name: "mural", fields: ["formatVersion": .string("3")]))
                == nil)
        #expect(
            CardRecordMapping.boardFormatVersion(from: SyncFixtures.record(.mural, name: "mural", fields: ["formatVersion": .double(3)]))
                == nil)
        #expect(
            CardRecordMapping.boardFormatVersion(
                from: SyncFixtures.record(.card, name: UUID().uuidString, fields: ["formatVersion": .int(3)]))
                == nil)
        let record = SyncFixtures.record(.mural, name: "mural", fields: ["formatVersion": .int(newer)])
        #expect(
            CardRecordMapping.boardFormatVersion(from: record) == Board.currentFormatVersion + 1,
            "mural de app mais novo: o motor recusa editar")
    }
}
