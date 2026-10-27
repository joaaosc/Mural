import Foundation
import MuralKit
import MuralSync
import Testing

/// Dois Macs (o dono e um convidado) editando o mesmo mural sobre o iCloud falso. Cada cenário termina sincronizando em rodadas até
/// nada mudar (no máximo 10; passar disso é eco) e conferindo que os dois murais ficaram iguais.
@Suite("iCloud: dois Macs no mesmo mural")
struct TwoMacsTests {
    private static let imageFile = "AAAAAAAA-0000-4000-8000-000000000001.jpg"

    // MARK: Ajudantes

    private func date(_ offset: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: 780_000_000 + offset)
    }

    private func note(_ title: String = "Nota", text: String = "Texto", x: Double = 10, y: Double = 20) -> BoardItem {
        BoardItem(kind: .text, title: title, createdAt: SyncFixtures.fractionalDate, position: BoardPoint(x: x, y: y), text: text)
    }

    private func sticky(_ text: String, x: Double = 10, y: Double = 20) -> BoardItem {
        BoardItem(
            kind: .sticky, title: ContentClassifier.title(forText: text), createdAt: SyncFixtures.otherFractionalDate,
            position: BoardPoint(x: x, y: y), text: text, stickyColor: .yellow)
    }

    private func image(_ title: String = "Foto", file: String = TwoMacsTests.imageFile) -> BoardItem {
        BoardItem(
            kind: .image, title: title, createdAt: SyncFixtures.thirdFractionalDate, position: BoardPoint(x: 50, y: 50), fileName: file)
    }

    private func board(_ items: BoardItem...) -> Board {
        var board = Board()
        for item in items { board.add(item) }
        return board
    }

    /// Muda um cartão da lista pelo `Board.update`, como o app faz ao editar.
    private func change(_ board: inout Board, _ id: UUID, _ transform: (inout BoardItem) -> Void) {
        guard var item = board.item(id: id) else { return }
        transform(&item)
        board.update(item)
    }

    /// Confere que a edição mudou o mural: os métodos de `Board` devolvem `false` quando nada muda. Fora do `#expect` porque o
    /// argumento da edição (`$0`) não pode entrar na macro.
    private func succeeds(
        _ changed: Bool, _ comment: Comment = "a edição não mudou o mural", sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(changed, comment, sourceLocation: sourceLocation)
    }

    private func titles(_ board: Board) -> Set<String> {
        Set(board.items.map(\.title))
    }

    // MARK: Gravação que falha

    @Test("Gravação que falha no Mac da convidada: nada se perde nem é apagado, e a busca completa a põe em dia, com o apagamento de lá")
    func failedLocalSaveRecoversThroughAFullFetch() async throws {
        let first = note("Primeira", x: 10)
        let second = note("Segunda", x: 200)
        let macs = try await TwoMacs.make(board: board(first, second))
        defer { macs.cleanUp() }
        try await macs.settle()

        let arrived = note("Nova do dono", x: 400)
        try await macs.owner.edit { board in
            board.add(arrived)
            _ = board.remove(id: second.id)
        }
        try await macs.owner.engine.sendChanges()
        let cloudBefore = await macs.cloudRecords()

        await macs.guest.host.failNextApply()
        try await macs.guest.engine.fetchChanges()

        #expect(await macs.guest.coordinator.issues()[macs.guest.boardID] == .localSaveFailed)
        #expect(Set(await macs.guest.board.items.map(\.id)) == [first.id, second.id], "o Mac dela continua como estava")
        try await macs.guest.engine.sendChanges()
        #expect(await macs.cloudRecords() == cloudBefore, "nada subiu do Mac dela, nem o apagamento do que chegou")

        try await macs.settle()
        await macs.expectConverged()
        #expect(Set(await macs.guest.board.items.map(\.id)) == [first.id, arrived.id])
    }

    // MARK: O que chega

    @Test("O dono põe o mural e o convidado recebe tudo: cartões, pasta, tamanhos, textos livres, nome e a mídia em Items/")
    func guestReceivesEverythingIncludingMedia() async throws {
        let folder = BoardItem(kind: .folder, title: "Pasta", createdAt: date(1), position: BoardPoint(x: 300, y: 40))
        var inside = sticky("Dentro da pasta")
        inside.parentID = folder.id
        inside.folderPosition = BoardPoint(x: 8, y: 12)
        var large = sticky("Grande", x: 400, y: 200)
        large.size = BoardSize(width: 220, height: 220)
        var initial = board(folder, inside, image(), note("Nota", text: "Primeira\nSegunda"), large)
        initial.add(
            BoardFreeText(
                text: "Solto", position: BoardPoint(x: 120, y: 90), createdAt: date(9), size: BoardSize(width: 260, height: 260)))

        let macs = try await TwoMacs.make(board: initial, name: "Casa", files: [Self.imageFile])
        defer { macs.cleanUp() }
        try await macs.settle()

        await macs.expectConverged()
        let received = await macs.guest.board
        #expect(received.items.map(SharedFieldPolicy.shared) == initial.items.map(SharedFieldPolicy.shared))
        #expect(Set(received.freeTexts) == Set(initial.freeTexts) && received.freeTexts.first?.size?.width == 260)
        #expect(await macs.guest.name == "Casa")
        #expect(macs.guest.fileContents(Self.imageFile) == "conteúdo de \(Self.imageFile)")
        #expect(await macs.cloudRecords().allSatisfy { $0.creatorUserRecordName == TwoMacs.ownerUser }, "só o dono criou registros")
    }

    @Test("Cada um cria cartões: depois das rodadas os dois Macs têm os cartões dos dois, na mesma ordem")
    func eachCreatesCards() async throws {
        let macs = try await TwoMacs.make(board: board(note("Base")))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.owner.edit { $0.add(note("Do dono", x: 100)) }
        try await macs.guest.edit { $0.add(note("Da convidada", x: 200)) }
        try await macs.guest.edit { $0.add(sticky("Post-it da convidada", x: 300)) }
        try await macs.settle()

        await macs.expectConverged()
        #expect(titles(await macs.owner.board) == ["Base", "Do dono", "Da convidada", "Post-it da convidada"])
        let creators = Set(await macs.cloudRecords().filter { $0.type == "Card" }.compactMap(\.creatorUserRecordName))
        #expect(creators == [TwoMacs.ownerUser, TwoMacs.guestUser], "o servidor guarda quem criou cada cartão")
    }

    @Test("Os dois editam campos diferentes do mesmo cartão: as duas edições ficam, sem cópia")
    func differentFieldsOfTheSameCard() async throws {
        let target = note("Nota", text: "Texto")
        let macs = try await TwoMacs.make(board: board(target))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.owner.edit { change(&$0, target.id) { $0.tag = "CLIENT 001" } }
        try await macs.guest.edit { change(&$0, target.id) { $0.colorTag = .purple } }
        try await macs.settle()

        await macs.expectConverged()
        for mac in [macs.owner, macs.guest] {
            let merged = try #require(await mac.board.item(id: target.id))
            #expect(merged.tag == "CLIENT 001" && merged.colorTag == .purple && merged.text == "Texto")
            #expect(await mac.board.items.count == 1)
        }
    }

    @Test("A mesma nota em parágrafos diferentes: as duas edições entram no texto, nos dois Macs")
    func sameNoteDifferentParagraphsMerge() async throws {
        let target = note("Nota", text: "Linha 1\nLinha 2\nLinha 3\nLinha 4\nLinha 5")
        let macs = try await TwoMacs.make(board: board(target))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.owner.edit { change(&$0, target.id) { $0.text = "Linha 1 do dono\nLinha 2\nLinha 3\nLinha 4\nLinha 5" } }
        try await macs.guest.edit { change(&$0, target.id) { $0.text = "Linha 1\nLinha 2\nLinha 3\nLinha 4\nLinha 5 da convidada" } }
        try await macs.settle()

        await macs.expectConverged()
        let expected = "Linha 1 do dono\nLinha 2\nLinha 3\nLinha 4\nLinha 5 da convidada"
        for mac in [macs.owner, macs.guest] {
            #expect(await mac.board.items.map(\.text) == [expected])
        }
    }

    @Test(
        "A mesma linha editada nos dois: o que chegou ao iCloud primeiro fica no cartão e o outro texto vira uma cópia de conflito nos dois"
    )
    func sameLineMakesAConflictCopyInBoth() async throws {
        let target = note("Nota", text: "Linha 1\nLinha 2\nLinha 3")
        let macs = try await TwoMacs.make(board: board(target))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.owner.edit { change(&$0, target.id) { $0.text = "Linha 1\nLinha 2 do dono\nLinha 3" } }
        try await macs.guest.edit { change(&$0, target.id) { $0.text = "Linha 1\nLinha 2 da convidada\nLinha 3" } }
        try await macs.owner.engine.sendChanges()
        try await macs.settle()

        await macs.expectConverged()
        for mac in [macs.owner, macs.guest] {
            let items = await mac.board.items
            #expect(items.count == 2)
            #expect(items.first { $0.id == target.id }?.text == "Linha 1\nLinha 2 do dono\nLinha 3")
            let copy = try #require(items.first { $0.id != target.id })
            #expect(copy.text == "Linha 1\nLinha 2 da convidada\nLinha 3")
            #expect(copy.title.hasSuffix("(cópia de conflito)"))
        }
        let ownerCopyIDs = Set(await macs.owner.board.items.map(\.id))
        #expect(ownerCopyIDs == Set(await macs.guest.board.items.map(\.id)), "a cópia tem o mesmo id nos dois")
    }

    @Test(
        "Apagar × editar a nota: quem apagou chegou primeiro ao iCloud, e o texto de quem editou fica numa cópia nos dois Macs",
        arguments: [true, false])
    func deleteVersusEditKeepsACopy(ownerDeletes: Bool) async throws {
        let target = note("Nota", text: "Original")
        let macs = try await TwoMacs.make(board: board(target))
        defer { macs.cleanUp() }
        try await macs.settle()
        let deleter = ownerDeletes ? macs.owner : macs.guest
        let editor = ownerDeletes ? macs.guest : macs.owner

        try await deleter.edit { _ = $0.remove(id: target.id) }
        try await editor.edit { change(&$0, target.id) { $0.text = "Editado por \(editor.user)" } }
        try await deleter.engine.sendChanges()
        try await macs.settle()

        await macs.expectConverged()
        for mac in [macs.owner, macs.guest] {
            let items = await mac.board.items
            #expect(items.count == 1 && items.first?.id != target.id)
            #expect(items.first?.text == "Editado por \(editor.user)")
        }
        #expect(await macs.cloudRecord(target.id.uuidString) == nil, "o cartão original continua apagado no iCloud")
        #expect(await macs.cloudRecords().filter { $0.type == "Card" }.count == 1)
    }

    @Test("Pasta apagada por um enquanto o outro põe um cartão nela: o cartão vai ao mural nos dois Macs", arguments: [true, false])
    func cardInADeletedFolderGoesToTheBoard(deleterSendsFirst: Bool) async throws {
        let folder = BoardItem(kind: .folder, title: "Pasta", createdAt: date(1), position: BoardPoint(x: 300, y: 40))
        let card = note("Cartão", x: 40, y: 40)
        let macs = try await TwoMacs.make(board: board(folder, card))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.owner.edit { _ = $0.remove(id: folder.id) }
        try await macs.guest.edit { succeeds($0.moveIntoFolder(id: card.id, folderID: folder.id)) }
        if deleterSendsFirst {
            try await macs.owner.engine.sendChanges()
            try await macs.guest.engine.sendChanges()
        } else {
            try await macs.guest.engine.sendChanges()
            try await macs.owner.engine.sendChanges()
        }
        try await macs.settle()

        await macs.expectConverged()
        for mac in [macs.owner, macs.guest] {
            let items = await mac.board.items
            #expect(items.map(\.id) == [card.id] && items.first?.parentID == nil)
        }
        #expect(await macs.cloudRecord(folder.id.uuidString) == nil)
    }

    @Test(
        "Levar ao topo: o cartão vai para o fim da lista nos dois Macs, e dois cartões levados ao topo ao mesmo tempo ficam na mesma ordem")
    func bringToFrontKeepsTheSameOrder() async throws {
        let first = note("A", x: 10)
        let second = note("B", x: 20)
        let third = note("C", x: 30)
        let macs = try await TwoMacs.make(board: board(first, second, third))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.guest.edit { _ = $0.move(id: first.id, to: BoardPoint(x: 500, y: 60)) }
        try await macs.settle()
        await macs.expectConverged()
        #expect(await macs.owner.board.items.map(\.id) == [second.id, third.id, first.id])
        #expect(await macs.guest.board.items.map(\.id) == [second.id, third.id, first.id])
        #expect(await macs.owner.board.item(id: first.id)?.position == BoardPoint(x: 500, y: 60))

        try await macs.owner.edit { _ = $0.move(id: second.id, to: BoardPoint(x: 60, y: 300)) }
        try await macs.guest.edit { _ = $0.move(id: third.id, to: BoardPoint(x: 70, y: 310)) }
        try await macs.settle()
        await macs.expectConverged()
        let order = await macs.owner.board.items.map(\.id)
        #expect(Set(order) == [first.id, second.id, third.id])
        #expect(order == (await macs.guest.board.items.map(\.id)))
    }

    @Test("Renomear o mural: o nome novo chega ao outro Mac, e de dois nomes ao mesmo tempo vale o último a chegar ao iCloud")
    func renameTheBoard() async throws {
        let macs = try await TwoMacs.make(board: board(note()), name: "Casa")
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.owner.rename("Casa nova")
        try await macs.settle()
        #expect(await macs.guest.name == "Casa nova")
        await macs.expectConverged()

        try await macs.owner.rename("Nome do dono")
        try await macs.guest.rename("Nome da convidada")
        try await macs.settle()
        await macs.expectConverged()
        // A rodada envia o dono antes da convidada: o nome dela chega por último, depois do conflito com o do dono.
        #expect(await macs.owner.name == "Nome da convidada")
    }

    @Test("Os dois redimensionam o mesmo post-it: vale a mudança que chegou por último ao iCloud no Mac que junta, e os dois ficam iguais")
    func bothResizeTheSameSticky() async throws {
        let target = sticky("Post-it")
        let macs = try await TwoMacs.make(board: board(target))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.owner.edit { succeeds($0.resize(id: target.id, to: BoardSize(width: 160, height: 160))) }
        try await macs.guest.edit { succeeds($0.resize(id: target.id, to: BoardSize(width: 220, height: 220))) }
        try await macs.owner.engine.sendChanges()
        try await macs.settle()

        await macs.expectConverged()
        for mac in [macs.owner, macs.guest] {
            #expect(await mac.board.item(id: target.id)?.size == BoardSize(width: 220, height: 220))
        }
        let record = try #require(await macs.cloudRecord(target.id.uuidString))
        guard case .card(let stored, _) = try CardRecordMapping.card(from: record) else {
            Issue.record("o registro do post-it não é de um cartão suportado")
            return
        }
        #expect(stored.size == BoardSize(width: 220, height: 220), "o iCloud guarda a mudança que chegou por último")
    }

    @Test("Textos livres: criar, redimensionar, mover, editar e apagar chegam ao outro Mac, e o nome do registro segue o id do texto")
    func freeTextsFollowTheOtherMac() async throws {
        let text = BoardFreeText(text: "Lembrete", position: BoardPoint(x: 100, y: 100), createdAt: date(5))
        var initial = board(note())
        initial.add(text)
        let macs = try await TwoMacs.make(board: initial)
        defer { macs.cleanUp() }
        try await macs.settle()
        await macs.expectConverged()

        try await macs.guest.edit { succeeds($0.resizeFreeText(id: text.id, to: BoardSize(width: 260, height: 260))) }
        try await macs.settle()
        #expect(await macs.owner.board.freeText(id: text.id)?.size == BoardSize(width: 260, height: 260))

        try await macs.owner.edit { succeeds($0.moveFreeText(id: text.id, to: BoardPoint(x: 300, y: 200))) }
        try await macs.settle()
        #expect(await macs.guest.board.freeText(id: text.id)?.position == BoardPoint(x: 300, y: 200))

        try await macs.guest.edit {
            guard var edited = $0.freeText(id: text.id) else { return }
            edited.text = "Lembrete novo"
            $0.update(edited)
        }
        try await macs.guest.edit { $0.add(BoardFreeText(text: "Da convidada", position: BoardPoint(x: 50, y: 400), createdAt: date(6))) }
        try await macs.settle()
        await macs.expectConverged()
        #expect(Set(await macs.owner.board.freeTexts.map(\.text)) == ["Lembrete novo", "Da convidada"])

        try await macs.owner.edit { succeeds($0.removeFreeText(id: text.id)) }
        try await macs.settle()
        await macs.expectConverged()
        #expect(await macs.guest.board.freeTexts.map(\.text) == ["Da convidada"])
        #expect(await macs.cloudRecord(text.id.uuidString) == nil)
    }

    // MARK: App mais novo

    @Test("Registros de app mais novo postos direto no iCloud não aparecem em nenhum Mac e nunca são apagados nem regravados")
    func newerAppRecordsStayUntouched() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota do dono"), sticky("Post-it")))
        defer { macs.cleanUp() }
        try await macs.settle()

        let newerVersion = CloudValue.int(Int64(Board.currentFormatVersion + 1))
        let newerCard = note("De app novo")
        var cardFields = try CardRecordMapping.fields(for: newerCard, layer: 1000)
        cardFields[CloudSchema.Key.formatVersion.rawValue] = newerVersion
        let newerText = BoardFreeText(text: "Texto de app novo", position: BoardPoint(x: 80, y: 80), createdAt: date(3))
        var textFields = CardRecordMapping.fields(for: newerText)
        textFields[CloudSchema.Key.formatVersion.rawValue] = newerVersion
        let sent = await macs.cloud.send(
            saving: [
                CloudRecord(
                    id: CloudRecordID(zone: macs.ownerZone, name: newerCard.id.uuidString), type: CloudSchema.RecordType.card.rawValue,
                    fields: cardFields),
                CloudRecord(
                    id: CloudRecordID(zone: macs.ownerZone, name: newerText.id.uuidString),
                    type: CloudSchema.RecordType.freeText.rawValue, fields: textFields),
            ], deleting: [], as: TwoMacs.ownerUser)
        #expect(sent.failures.isEmpty && sent.saved.count == 2)
        let newerNames: Set<String> = [newerCard.id.uuidString, newerText.id.uuidString]

        // Nenhum dos dois Macs mexe nesses registros, nem ao apagar todos os cartões que entende.
        try await macs.owner.edit { board in
            for item in board.items { _ = board.remove(id: item.id) }
        }
        try await macs.guest.edit { $0.add(note("Da convidada")) }
        try await macs.settle()
        try await macs.settle()

        await macs.expectConverged()
        for mac in [macs.owner, macs.guest] {
            let board = await mac.board
            #expect(!board.items.contains { newerNames.contains($0.id.uuidString) })
            #expect(!board.freeTexts.contains { newerNames.contains($0.id.uuidString) })
            let state = try #require(try await mac.store.state(for: macs.boardID))
            #expect(state.unsupportedRecordNames == newerNames, "o Mac sabe que são de app mais novo")
        }
        let kept = Set(await macs.cloudRecords().filter { newerNames.contains($0.id.name) })
        #expect(kept == Set(sent.saved), "continuam no iCloud, iguais, com a mesma marca de alteração")
        #expect(await macs.cloudRecords().filter { $0.type == "Card" }.count == 2, "o cartão da convidada e o de app mais novo")
    }

    // MARK: Permissões e zona

    @Test("Convidado só leitura com a permissão desatualizada tenta gravar: a recusa vira aviso, o iCloud fica igual e nada sobra pendente")
    func readOnlyGuestCannotWrite() async throws {
        let macs = try await TwoMacs.make(
            board: board(note("Base")), guestPermission: .readOnly, guestTracksAs: .readWrite, guestSendsInitialPending: false)
        defer { macs.cleanUp() }
        try await macs.settle()
        await macs.expectConverged()
        let before = await macs.cloudRecords()

        try await macs.guest.edit { $0.add(note("Do convidado")) }
        try await macs.guest.engine.sendChanges()

        #expect(await macs.guest.coordinator.issues()[macs.boardID] == .readOnly)
        #expect(await macs.cloudRecords() == before, "o iCloud falso fica igual")
        #expect(await macs.guest.engine.pending.isEmpty)

        // A recusa vale até a permissão nova chegar: outra edição não volta a tentar.
        try await macs.guest.edit { $0.add(note("Outra do convidado")) }
        #expect(await macs.guest.engine.pending.isEmpty)
        #expect(try await macs.guest.engine.sendChanges() == 0)

        let info = BoardCloudInfo(
            database: .shared, zoneName: macs.zoneName, zoneOwnerName: TwoMacs.ownerUser, ownerDisplayName: "Ana", permission: .readOnly)
        let pending = try await macs.guest.coordinator.startTracking(macs.boardID, cloud: info)
        #expect(pending.isEmpty, "só leitura não envia nada")
        await macs.guest.engine.add(pending)
        try await macs.guest.edit { $0.add(note("Mais uma")) }
        #expect(try await macs.guest.engine.sendChanges() == 0)
        #expect(await macs.cloudRecords() == before)

        // A edição dele fica só no Mac dele; o dono não a vê, e o que o dono faz continua chegando.
        try await macs.owner.edit { $0.add(note("Do dono")) }
        try await macs.settle()
        #expect(titles(await macs.owner.board) == ["Base", "Do dono"])
        #expect(titles(await macs.guest.board) == ["Base", "Do dono", "Do convidado", "Outra do convidado", "Mais uma"])
    }

    @Test("O dono apaga a zona: o convidado recebe boardRemoved(.zoneDeleted) e deixa de acompanhar o mural; o dono também")
    func zoneDeletedRemovesTheBoard() async throws {
        let macs = try await TwoMacs.make(board: board(note()))
        defer { macs.cleanUp() }
        try await macs.settle()

        await macs.cloud.deleteZone(macs.zoneName, owner: TwoMacs.ownerUser)
        try await macs.guest.engine.fetchChanges()
        try await macs.owner.engine.fetchChanges()

        for mac in [macs.owner, macs.guest] {
            #expect(await mac.host.removals == [SyncTestHost.Removal(board: macs.boardID, reason: .zoneDeleted)])
            #expect(try await mac.coordinator.boardIDs().isEmpty)
            #expect(try await mac.store.state(for: macs.boardID) == nil)
            #expect(await mac.engine.pending.isEmpty)
        }
    }

    @Test("O dono tira o convite: o convidado recebe boardRemoved(.accessRevoked) e o dono continua com o mural")
    func revokedGuestLosesTheBoard() async throws {
        let macs = try await TwoMacs.make(board: board(note()))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.cloud.revoke(zone: macs.zoneName, owner: TwoMacs.ownerUser, from: TwoMacs.guestUser)
        try await macs.guest.engine.fetchChanges()
        try await macs.owner.engine.fetchChanges()

        #expect(await macs.guest.host.removals == [SyncTestHost.Removal(board: macs.boardID, reason: .accessRevoked)])
        #expect(try await macs.guest.coordinator.boardIDs().isEmpty)
        #expect(await macs.owner.host.removals.isEmpty)
        #expect(try await macs.owner.coordinator.boardIDs() == [macs.boardID])
        #expect(await macs.cloudRecords().isEmpty == false, "o mural continua no iCloud do dono")
    }

    @Test("Enviar para uma zona que o dono apagou: o convidado recebe boardRemoved(.zoneDeleted) pelo envio e nada fica pendente")
    func sendingToADeletedZoneRemovesTheBoard() async throws {
        let macs = try await TwoMacs.make(board: board(note()))
        defer { macs.cleanUp() }
        try await macs.settle()

        await macs.cloud.deleteZone(macs.zoneName, owner: TwoMacs.ownerUser)
        try await macs.guest.edit { $0.add(note("Tarde demais")) }
        try await macs.guest.engine.sendChanges()

        #expect(await macs.guest.host.removals == [SyncTestHost.Removal(board: macs.boardID, reason: .zoneDeleted)])
        #expect(try await macs.guest.coordinator.boardIDs().isEmpty)
        #expect(await macs.guest.engine.pending.isEmpty)
        #expect(await macs.guest.coordinator.issues().isEmpty)
    }

    @Test(
        "Zona de um mural que o Mac já tem como pacote local, sem acompanhar: a adoção dá conflito, o motor não a busca e o que chegou antes de acompanhar não se perde"
    )
    func untrackedZonesAreNotFetched() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")))
        defer { macs.cleanUp() }
        try await macs.settle()
        try await macs.cloud.share(zone: macs.zoneName, owner: TwoMacs.ownerUser, with: "caio", permission: .readWrite)
        let third = try await TestMac.make(
            user: "caio", scope: .shared, cloud: macs.cloud, boardID: macs.boardID, name: "Casa")
        defer { try? FileManager.default.removeItem(at: third.root) }

        try await third.engine.fetchChanges()
        #expect(await third.board.items.isEmpty, "o mural ainda não é acompanhado: nada é entregue")
        #expect(await third.host.adoptions.count == 1, "o motor tentou adotar, e o host recusou: o id já existe")
        #expect(try await third.coordinator.isTracking(macs.boardID) == false)

        let info = BoardCloudInfo(
            database: .shared, zoneName: macs.zoneName, zoneOwnerName: TwoMacs.ownerUser, ownerDisplayName: "Ana", permission: .readWrite)
        await third.engine.add(try await third.coordinator.startTracking(macs.boardID, cloud: info))
        try await third.engine.fetchChanges()
        #expect(titles(await third.board) == ["Nota"])
    }

    @Test("Só o dono cria a zona: o motor do convidado recusa startZone")
    func onlyTheOwnerStartsAZone() async throws {
        let macs = try await TwoMacs.make()
        defer { macs.cleanUp() }
        await #expect(throws: InMemorySyncEngineError.notOwner) {
            try await macs.guest.engine.startZone(for: macs.boardID)
        }
    }

    // MARK: Zona nova

    /// O segundo Mac do dono, já com o mural adotado e buscado inteiro. Quem chama apaga `root`.
    private func adoptedSecondMac(of macs: TwoMacs) async throws -> TestMac {
        let second = try await macs.makeSecondOwnerMac()
        try await second.engine.fetchChanges()
        return second
    }

    @Test("Segundo Mac do dono: a busca adota a zona sozinha, traz tudo (nome, cartões e mídia) e não envia nada")
    func ownersSecondMacAdoptsTheZoneOnItsOwn() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota"), image()), name: "Casa", files: [Self.imageFile])
        defer { macs.cleanUp() }
        try await macs.settle()
        let second = try await macs.makeSecondOwnerMac()
        defer { try? FileManager.default.removeItem(at: second.root) }
        let cloudBefore = await macs.cloudRecords()
        #expect(await second.host.hasBoard(macs.boardID) == false)

        try await second.engine.fetchChanges()

        let ownerInfo = BoardCloudInfo(
            database: .private, zoneName: macs.zoneName, zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner)
        #expect(await second.host.adoptions == [SyncTestHost.Adoption(board: macs.boardID, cloud: ownerInfo, name: nil)])
        #expect(await second.name == "Casa", "o nome provisório foi trocado pelo do dono")
        #expect(await second.board.items.map(SharedFieldPolicy.shared) == (await macs.owner.board).items.map(SharedFieldPolicy.shared))
        #expect(second.fileContents(Self.imageFile) == "conteúdo de \(Self.imageFile)")
        let state = try #require(try await second.store.state(for: macs.boardID))
        #expect(!state.isAwaitingFirstFetch && !state.needsFullFetch && state.cloud == ownerInfo)
        #expect(await second.coordinator.issues().isEmpty)
        #expect(await second.engine.pending.isEmpty)
        #expect(await macs.cloudRecords() == cloudBefore, "o segundo Mac não enviou nada")
    }

    @Test("Zona adotada ainda sem o registro do mural: o segundo Mac nunca cria o nome, e recebe o do dono quando ele chega")
    func adoptedBoardNeverCreatesTheBoardRecord() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")), name: "Casa")
        defer { macs.cleanUp() }
        // A zona existe, mas o dono ainda não enviou nada: a primeira busca do segundo Mac termina sem o registro do mural.
        let second = try await macs.makeSecondOwnerMac()
        defer { try? FileManager.default.removeItem(at: second.root) }
        let ownerInfo = BoardCloudInfo(
            database: .private, zoneName: macs.zoneName, zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner)
        #expect(try await second.coordinator.adoptZone(macs.ownerZone, cloud: ownerInfo, name: "Nome provisório") == .adopted)
        try await second.engine.fetchChanges()

        let state = try #require(try await second.store.state(for: macs.boardID))
        #expect(!state.isAwaitingFirstFetch && state.isAdopted && state.baseName == nil)
        #expect(try await second.coordinator.pendingChanges(for: macs.boardID).isEmpty, "o nome provisório não vira registro")
        await second.engine.add(try await second.coordinator.pendingChanges(for: macs.boardID))
        try await second.engine.sendChanges()
        #expect(await macs.cloudRecord(CloudSchema.muralRecordName) == nil)

        try await macs.settle(including: second)
        #expect(await second.name == "Casa")
        let mural = try #require(await macs.cloudRecord(CloudSchema.muralRecordName))
        #expect(CardRecordMapping.boardName(from: mural) == "Casa")
    }

    @Test("Segundo Mac do dono: depois de adotar, as edições dos três Macs convergem")
    func ownersSecondMacConvergesWithTheOthers() async throws {
        let macs = try await TwoMacs.make(board: board(note("Base")), name: "Casa")
        defer { macs.cleanUp() }
        try await macs.settle()
        let second = try await adoptedSecondMac(of: macs)
        defer { try? FileManager.default.removeItem(at: second.root) }

        try await second.edit { $0.add(note("Do segundo Mac", x: 200)) }
        try await macs.owner.edit { $0.add(note("Do primeiro Mac", x: 300)) }
        try await macs.guest.edit { $0.add(note("Do convidado", x: 400)) }
        try await macs.settle(including: second)

        await macs.expectConverged()
        let expected: Set<String> = ["Base", "Do segundo Mac", "Do primeiro Mac", "Do convidado"]
        #expect(titles(await second.board) == expected)
        #expect(titles(await macs.owner.board) == expected)
        #expect(await second.board.items.map(SharedFieldPolicy.shared) == (await macs.owner.board).items.map(SharedFieldPolicy.shared))
        #expect(await second.name == (await macs.owner.name))
        #expect(await second.coordinator.issues().isEmpty)
        let secondBoard = await second.board
        TwoMacs.expectValidStructure(secondBoard, owner: "segundo Mac do dono")
    }

    @Test("O nome provisório do Mac que adota nunca sobe: o registro do mural no iCloud fica com o nome e a marca do dono")
    func provisionalNameNeverReachesTheCloud() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")), name: "Casa do dono")
        defer { macs.cleanUp() }
        try await macs.settle()
        let before = try #require(await macs.cloudRecord(CloudSchema.muralRecordName))
        let second = try await macs.makeSecondOwnerMac()
        defer { try? FileManager.default.removeItem(at: second.root) }

        // Adotado e ainda sem a primeira busca: o pacote tem um nome provisório e nada sobe, nem se o motor tentar.
        let ownerInfo = BoardCloudInfo(
            database: .private, zoneName: macs.zoneName, zoneOwnerName: CloudZoneID.defaultOwnerName, permission: .owner)
        let adopted = try await second.coordinator.adoptZone(macs.ownerZone, cloud: ownerInfo, name: "Nome provisório")
        #expect(adopted == .adopted)
        await second.engine.add(try await second.coordinator.pendingChanges(for: macs.boardID))
        try await second.engine.sendChanges()
        #expect(await macs.cloudRecord(CloudSchema.muralRecordName) == before)
        #expect(await second.name == "Nome provisório")

        try await macs.settle(including: second)

        let after = try #require(await macs.cloudRecord(CloudSchema.muralRecordName))
        #expect(after == before, "nem o conteúdo nem a marca de alteração do registro mudaram")
        #expect(CardRecordMapping.boardName(from: after) == "Casa do dono")
        #expect(await second.name == "Casa do dono")
        await macs.expectConverged()
    }

    @Test(
        "Convidado que só foi convidado: a busca adota a zona como só leitura e, depois da primeira busca, vale a permissão do iCloud",
        arguments: [InMemoryCloud.GuestPermission.readWrite, .readOnly])
    func guestAdoptsAsReadOnlyAndThenGetsTheGrantedPermission(granted: InMemoryCloud.GuestPermission) async throws {
        let macs = try await TwoMacs.make(
            board: board(note("Base")), name: "Casa", guestPermission: granted, guestAdopts: true)
        defer { macs.cleanUp() }
        try await macs.owner.engine.sendChanges()
        #expect(await macs.guest.host.hasBoard(macs.boardID) == false)

        try await macs.guest.engine.fetchChanges()

        let adoptedAs = BoardCloudInfo(
            database: .shared, zoneName: macs.zoneName, zoneOwnerName: TwoMacs.ownerUser, permission: .readOnly)
        #expect(await macs.guest.host.adoptions == [SyncTestHost.Adoption(board: macs.boardID, cloud: adoptedAs, name: nil)])
        #expect(await macs.guest.name == "Casa")
        #expect(titles(await macs.guest.board) == ["Base"])
        let state = try #require(try await macs.guest.store.state(for: macs.boardID))
        let expectedPermission: BoardCloudInfo.Permission = granted == .readWrite ? .readWrite : .readOnly
        #expect(!state.isAwaitingFirstFetch && state.cloud.permission == expectedPermission && state.cloud.database == .shared)
        #expect(await macs.guest.coordinator.issues().isEmpty)

        try await macs.guest.edit { $0.add(note("Do convidado", x: 200)) }
        try await macs.settle()

        if granted == .readWrite {
            await macs.expectConverged()
            #expect(titles(await macs.owner.board) == ["Base", "Do convidado"], "depois da primeira busca ele passa a editar")
        } else {
            #expect(titles(await macs.owner.board) == ["Base"], "só leitura: a edição fica no Mac dele")
            #expect(titles(await macs.guest.board) == ["Base", "Do convidado"])
            #expect(await macs.guest.engine.pending.isEmpty)
            #expect(await macs.guest.coordinator.issues().isEmpty)
        }
    }

    @Test("Zona recusada não é adotada de novo pelo motor, e a recusa acaba quando o dono apaga a zona")
    func declinedZoneStaysOutUntilTheServerDeletesIt() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")))
        defer { macs.cleanUp() }
        try await macs.settle()
        let second = try await adoptedSecondMac(of: macs)
        defer { try? FileManager.default.removeItem(at: second.root) }
        #expect(try await second.coordinator.isTracking(macs.boardID))

        // O segundo Mac abandona o mural sem apagar o do iCloud.
        try await second.coordinator.declineZone(of: macs.boardID)
        try await second.coordinator.stopTracking(macs.boardID)
        try await second.engine.fetchChanges()

        #expect(try await second.coordinator.isTracking(macs.boardID) == false)
        #expect(await second.host.adoptions.count == 1, "o motor não tentou adotar de novo")
        #expect(try await second.coordinator.declinedZones() == [macs.ownerZone])
        #expect(await macs.cloudRecords().isEmpty == false, "o mural continua no iCloud do dono")

        // O dono apaga o mural e a zona: o servidor confirmou, e a recusa deixa de valer.
        try await macs.owner.coordinator.stopTracking(macs.boardID)
        try await macs.owner.engine.deleteZone(for: macs.boardID)
        try await second.engine.fetchChanges()

        #expect(try await second.coordinator.declinedZones().isEmpty)
        #expect(await macs.cloud.zones(for: TwoMacs.ownerUser, scope: .private).isEmpty)
        #expect(await second.host.adoptions.count == 1)
    }

    @Test("O motor do dono apaga a zona: some o que estava pendente para ela, o convidado perde o mural e o motor dele recusa apagar")
    func ownerEngineDeletesTheZone() async throws {
        let macs = try await TwoMacs.make(board: board(note()))
        defer { macs.cleanUp() }
        try await macs.settle()
        try await macs.owner.edit { $0.add(note("Pendente", x: 300)) }
        #expect(await macs.owner.engine.pending.isEmpty == false)

        try await macs.owner.coordinator.stopTracking(macs.boardID)
        try await macs.owner.engine.deleteZone(for: macs.boardID)
        try await macs.guest.engine.fetchChanges()

        #expect(await macs.owner.engine.pending.isEmpty)
        #expect(await macs.cloudRecords().isEmpty)
        #expect(await macs.guest.host.removals == [SyncTestHost.Removal(board: macs.boardID, reason: .zoneDeleted)])
        #expect(try await macs.guest.coordinator.boardIDs().isEmpty)
        #expect(await macs.owner.host.removals.isEmpty, "quem apagou não recebe aviso de remoção")
        await #expect(throws: InMemorySyncEngineError.notOwner) {
            try await macs.guest.engine.deleteZone(for: macs.boardID)
        }
    }

    @Test("O convidado sai do mural: o acesso dele acaba no iCloud, o dono continua com tudo e a zona recusada não volta")
    func guestLeavesTheZone() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")))
        defer { macs.cleanUp() }
        try await macs.settle()

        try await macs.guest.coordinator.declineZone(of: macs.boardID)
        try await macs.guest.coordinator.stopTracking(macs.boardID)
        await macs.guest.engine.leaveZone(macs.guestZone)
        try await macs.guest.engine.fetchChanges()
        try await macs.owner.engine.fetchChanges()

        #expect(await macs.cloud.zones(for: TwoMacs.guestUser, scope: .shared).isEmpty)
        #expect(await macs.cloud.zones(for: TwoMacs.ownerUser, scope: .private) == [macs.ownerZone])
        #expect(await macs.guest.host.removals.isEmpty, "o convidado saiu por conta própria")
        #expect(await macs.guest.host.adoptions.isEmpty)
        #expect(try await macs.guest.coordinator.declinedZones().isEmpty, "o servidor confirmou: a zona sumiu para ele")
        #expect(titles(await macs.owner.board) == ["Nota"])
        #expect(await macs.cloudRecords().isEmpty == false)

        // O dono não tem de quem sair: `leaveZone` só vale para o convidado.
        await macs.owner.engine.leaveZone(macs.ownerZone)
        #expect(await macs.cloud.zones(for: TwoMacs.ownerUser, scope: .private) == [macs.ownerZone])
    }

    @Test("Host que não adota zonas: o motor deixa a zona de fora, sem erro, como antes da adoção")
    func engineSkipsZonesWhenTheHostCannotAdopt() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")))
        defer { macs.cleanUp() }
        try await macs.settle()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MuralNoAdoption-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SyncMetadataStore(directory: directory)
        let coordinator = BoardSyncCoordinator(scope: .private, store: store, host: SyncHostWithoutAdoption())
        let engine = InMemorySyncEngine(user: TwoMacs.ownerUser, scope: .private, cloud: macs.cloud, coordinator: coordinator)

        try await engine.fetchChanges()
        try await engine.fetchChanges()

        #expect(try await coordinator.boardIDs().isEmpty)
        #expect(await engine.pending.isEmpty)
        #expect(try await store.boardIDs().isEmpty)
    }

    // MARK: Convites

    @Test("Convites do motor falso: o convidado recebe a permissão, o dono e os convidados, e o dono recebe a si mesmo e os convidados")
    func fakeEngineDeliversTheShares() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")), guestPermission: .readOnly, guestTracksAs: .readOnly)
        defer { macs.cleanUp() }
        let ownerLog = ShareLog()
        let guestLog = ShareLog()
        await macs.owner.engine.setShareHandler { ownerLog.record($0) }
        await macs.guest.engine.setShareHandler { guestLog.record($0) }

        try await macs.owner.engine.sendChanges()
        try await macs.owner.engine.fetchChanges()
        try await macs.guest.engine.fetchChanges()

        let guest = ShareSummary.Participant(
            displayName: TwoMacs.guestUser, userRecordName: TwoMacs.guestUser, permission: .readOnly, isAccepted: true)
        #expect(
            ownerLog.all == [
                [
                    ShareSummary(
                        zone: macs.ownerZone, currentUserPermission: .owner, ownerDisplayName: TwoMacs.ownerUser,
                        ownerUserRecordName: TwoMacs.ownerUser, participants: [guest])
                ]
            ])
        #expect(
            guestLog.all == [
                [
                    ShareSummary(
                        zone: macs.guestZone, currentUserPermission: .readOnly, ownerDisplayName: TwoMacs.ownerUser,
                        ownerUserRecordName: TwoMacs.ownerUser, participants: [guest])
                ]
            ])

        // O dono passa o convidado a editar: o convite seguinte já traz a permissão nova, para os dois.
        try await macs.cloud.share(zone: macs.zoneName, owner: TwoMacs.ownerUser, with: TwoMacs.guestUser, permission: .readWrite)
        try await macs.guest.engine.fetchChanges()
        try await macs.owner.engine.fetchChanges()

        #expect(guestLog.all.last?.first?.currentUserPermission == .readWrite)
        #expect(ownerLog.all.last?.first?.participants.map(\.permission) == [.readWrite])
    }

    @Test("Convites do motor falso: o convidado recebe todos os convidados da zona, ordenados pelo nome, todos aceitos")
    func fakeEngineListsEveryGuestToTheGuest() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")), guestPermission: .readOnly, guestTracksAs: .readOnly)
        defer { macs.cleanUp() }
        let guestLog = ShareLog()
        await macs.guest.engine.setShareHandler { guestLog.record($0) }
        try await macs.cloud.share(zone: macs.zoneName, owner: TwoMacs.ownerUser, with: "caio", permission: .readWrite)
        try await macs.cloud.share(zone: macs.zoneName, owner: TwoMacs.ownerUser, with: "abel", permission: .readOnly)

        try await macs.guest.engine.fetchChanges()

        let share = try #require(guestLog.all.last?.first)
        #expect(share.ownerUserRecordName == TwoMacs.ownerUser)
        #expect(share.participants.map(\.userRecordName) == ["abel", TwoMacs.guestUser, "caio"], "pelo nome, com a própria pessoa")
        #expect(share.participants.map(\.displayName) == ["abel", TwoMacs.guestUser, "caio"])
        #expect(share.participants.map(\.permission) == [.readOnly, .readOnly, .readWrite])
        #expect(share.participants.allSatisfy { $0.isAccepted })
    }

    @Test("Convites do motor falso: a zona do dono sem convidado sai como apagada, e quem perdeu o acesso não recebe mais convite")
    func fakeEngineReportsAZoneWithoutGuestsAsDeleted() async throws {
        let macs = try await TwoMacs.make(board: board(note("Nota")))
        defer { macs.cleanUp() }
        try await macs.settle()
        let ownerLog = ShareLog()
        let guestLog = ShareLog()
        await macs.owner.engine.setShareHandler { ownerLog.record($0) }
        await macs.guest.engine.setShareHandler { guestLog.record($0) }

        try await macs.cloud.revoke(zone: macs.zoneName, owner: TwoMacs.ownerUser, from: TwoMacs.guestUser)
        try await macs.owner.engine.fetchChanges()
        try await macs.guest.engine.fetchChanges()

        #expect(ownerLog.all == [[ShareSummary(zone: macs.ownerZone, isDeleted: true)]])
        #expect(guestLog.all.isEmpty, "a zona já não aparece para o convidado")
        #expect(await macs.guest.host.removals == [SyncTestHost.Removal(board: macs.boardID, reason: .accessRevoked)])
    }

    // MARK: Envio confirmado só em parte

    /// O que o iCloud falso recusa de propósito na primeira tentativa.
    enum Refusal: CaseIterable, CustomStringConvertible {
        case boardRecord, card, mediaFile

        var description: String {
            switch self {
            case .boardRecord: "o registro do mural"
            case .card: "um cartão"
            case .mediaFile: "o arquivo de mídia"
            }
        }
    }

    @Test(
        "Envio confirmado só em parte: com uma gravação recusada na leva, o reenvio completa e os dois convergem",
        arguments: Refusal.allCases)
    func partialSaveIsCompletedByTheResend(refusal: Refusal) async throws {
        let note = note("Nota")
        let photo = image()
        let macs = try await TwoMacs.make(board: board(note, photo), files: [Self.imageFile])
        defer { macs.cleanUp() }
        let refused =
            switch refusal {
            case .boardRecord: CloudSchema.muralRecordName
            case .card: note.id.uuidString
            case .mediaFile: Self.imageFile
            }
        await macs.cloud.refuseNextSave(of: refused)

        let passes = try await macs.owner.engine.sendChanges()

        #expect(passes == 2, "a primeira leva passa em parte e a segunda leva o que sobrou (recusa: \(refusal))")
        #expect(await macs.owner.coordinator.issues().isEmpty, "a segunda leva, aceita sem recusa, limpa o aviso")
        #expect(await macs.cloudRecord(refused) != nil)
        try await macs.settle()
        await macs.expectConverged()
        #expect(titles(await macs.guest.board) == ["Nota", "Foto"])
        #expect(macs.guest.fileContents(Self.imageFile) == "conteúdo de \(Self.imageFile)")
    }

    @Test(
        "Envio confirmado só em parte: o iCloud recusa o apagamento do arquivo na leva em que apaga o cartão, e o reenvio não deixa arquivo órfão"
    )
    func partialDeleteLeavesNoOrphanFile() async throws {
        let photo = image()
        let macs = try await TwoMacs.make(board: board(note("Nota"), photo), files: [Self.imageFile])
        defer { macs.cleanUp() }
        try await macs.settle()
        await macs.expectConverged()
        #expect(await macs.cloudRecord(Self.imageFile) != nil)

        await macs.cloud.refuseNextDelete(of: Self.imageFile)
        try await macs.owner.edit { _ = $0.remove(id: photo.id) }
        #expect(
            await macs.owner.engine.pending == [
                .delete(CloudRecordID(zone: macs.ownerZone, name: photo.id.uuidString)),
                .delete(CloudRecordID(zone: macs.ownerZone, name: Self.imageFile)),
            ])
        let passes = try await macs.owner.engine.sendChanges()

        #expect(passes == 2)
        #expect(await macs.cloudRecord(Self.imageFile) == nil)
        try await macs.settle()
        await macs.expectConverged()
        #expect(titles(await macs.guest.board) == ["Nota"])
        #expect(await macs.orphanMediaFiles().isEmpty)
    }

    // MARK: Propriedade

    /// Uma edição pseudoaleatória: criar post-it, nota, pasta ou texto livre; editar texto; mover; levar ao topo; redimensionar;
    /// apagar; pôr em pasta. Tudo é sorteado antes, para a sequência de números não depender do ramo escolhido.
    private static func randomEdit(_ board: inout Board, _ random: inout SeededGenerator, serial: Int) {
        let stamp = Date(timeIntervalSinceReferenceDate: 780_000_000 + Double(serial))
        let roll = random.int(below: 100)
        let point = BoardPoint(x: Double(random.int(below: 1200)), y: Double(random.int(below: 800)))
        let pickA = random.int(below: 1000)
        let pickB = random.int(below: 1000)
        // Metade das escolhas cai nos três primeiros candidatos: os dois Macs mexem nos mesmos cartões e há conflitos de verdade.
        let favorsFirst = random.int(below: 2) == 0
        let id = random.uuid()
        let word = ["alfa", "beta", "gama", "delta", "épsilon"][random.int(below: 5)]

        let cards = board.items
        let freeTexts = board.freeTexts
        func index(among count: Int) -> Int {
            pickA % (favorsFirst ? min(count, 3) : count)
        }
        func card(_ matching: (BoardItem) -> Bool) -> BoardItem? {
            let candidates = cards.filter(matching)
            return candidates.isEmpty ? nil : candidates[index(among: candidates.count)]
        }
        func addSticky() {
            let text = "\(word) \(serial)"
            board.add(
                BoardItem(
                    id: id, kind: .sticky, title: ContentClassifier.title(forText: text), createdAt: stamp, position: point, text: text,
                    stickyColor: .yellow))
        }

        switch roll {
        case ..<12:
            addSticky()
        case ..<22:
            board.add(
                BoardItem(
                    id: id, kind: .text, title: "Nota \(serial)", createdAt: stamp, position: point,
                    text: "Linha 1 \(word)\nLinha 2\nLinha 3\nLinha 4"))
        case ..<26:
            board.add(BoardItem(id: id, kind: .folder, title: "Pasta \(serial)", createdAt: stamp, position: point))
        case ..<40:
            guard var target = card({ $0.kind == .sticky || $0.kind == .text }) else { return addSticky() }
            var lines = (target.text ?? "").split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            if lines.count > 1, pickB % 3 != 0 {
                lines[pickB % lines.count] = "editada \(word) \(serial)"
            } else {
                lines.append("linha \(serial)")
            }
            target.text = lines.joined(separator: "\n")
            if target.kind == .sticky { target.title = ContentClassifier.title(forText: target.text ?? "") }
            board.update(target)
        case ..<48:
            guard let target = card({ $0.parentID == nil }) else { return addSticky() }
            board.setPositions([target.id: point])
        case ..<56:
            guard let target = card({ $0.parentID == nil }) else { return addSticky() }
            board.move(id: target.id, to: point)
        case ..<62:
            guard let target = card({ $0.kind == .sticky }) else { return addSticky() }
            let side = BoardLayout.stickyPresetSides[pickB % BoardLayout.stickyPresetSides.count]
            board.resize(id: target.id, to: BoardSize(width: side, height: side))
        case ..<68:
            board.add(BoardFreeText(id: id, text: "texto \(word) \(serial)", position: point, createdAt: stamp))
        case ..<73:
            guard !freeTexts.isEmpty else { return addSticky() }
            var target = freeTexts[index(among: freeTexts.count)]
            target.text = "editado \(word) \(serial)"
            board.update(target)
        case ..<77:
            guard !freeTexts.isEmpty else { return addSticky() }
            board.moveFreeText(id: freeTexts[index(among: freeTexts.count)].id, to: point)
        case ..<81:
            guard !freeTexts.isEmpty else { return addSticky() }
            let side = BoardLayout.freeTextPresetSides[pickB % BoardLayout.freeTextPresetSides.count]
            board.resizeFreeText(id: freeTexts[index(among: freeTexts.count)].id, to: BoardSize(width: side, height: side))
        case ..<85:
            guard !freeTexts.isEmpty else { return addSticky() }
            board.removeFreeText(id: freeTexts[index(among: freeTexts.count)].id)
        case ..<91:
            guard let target = card({ _ in true }) else { return addSticky() }
            board.remove(id: target.id)
        default:
            let folders = cards.filter { $0.kind == .folder }
            guard !folders.isEmpty, let target = card({ _ in true }) else { return addSticky() }
            board.moveIntoFolder(id: target.id, folderID: folders[pickB % folders.count].id)
        }
    }

    @Test(
        "Propriedade: 50 rodadas de edições pseudoaleatórias nos dois Macs, com sincronização parcial no meio, terminam iguais e dentro do limite",
        arguments: [UInt64(1), 7, 42, 2026, 31_415])
    func randomEditsConverge(seed: UInt64) async throws {
        var random = SeededGenerator(seed: seed)
        let macs = try await TwoMacs.make(board: board(note("Base"), sticky("Primeiro post-it", x: 200)), name: "Casa")
        defer { macs.cleanUp() }
        try await macs.settle()

        var serial = 0
        for _ in 0..<50 {
            for mac in [macs.owner, macs.guest] {
                for _ in 0..<(1 + random.int(below: 2)) {
                    serial += 1
                    try await mac.edit { Self.randomEdit(&$0, &random, serial: serial) }
                }
            }
            switch random.int(below: 12) {
            case 0: try await macs.owner.engine.sendChanges()
            case 1: try await macs.guest.engine.sendChanges()
            case 2: try await macs.owner.engine.fetchChanges()
            case 3: try await macs.guest.engine.fetchChanges()
            default: break
            }
        }

        let rounds = try await macs.settle()
        #expect(rounds <= 10)
        await macs.expectConverged()
    }
}
