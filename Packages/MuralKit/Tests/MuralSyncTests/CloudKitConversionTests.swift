import CloudKit
import Foundation
import MuralKit
import Testing

@testable import MuralSync

/// A ponte com o CloudKit sem rede e sem container: só `CKRecord` e `CKError` montados à mão. O motor de verdade (`CKSyncEngine`) não
/// tem teste automático; o que decide está nos testes do coordenador, e aqui fica a tradução de tipos.
@Suite("Ponte com o CloudKit: conversão de registros e erros")
struct CloudKitConversionTests {
    private static let zoneName = SyncFixtures.zone.name

    // MARK: Auxiliares

    private func ckRecord(
        _ type: CloudSchema.RecordType = .card, name: String = UUID().uuidString, owner: String = CKCurrentUserDefaultName
    ) -> CKRecord {
        let zone = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: owner)
        return CKRecord(recordType: type.rawValue, recordID: CKRecord.ID(recordName: name, zoneID: zone))
    }

    private func set(_ record: CKRecord, _ key: String, _ value: any CKRecordValue) {
        record.setObject(value, forKey: key)
    }

    private func roundTrip(_ record: CloudRecord) throws -> CloudRecord {
        try CloudRecord(try record.makeCKRecord())
    }

    // MARK: Zona e identificador

    @Test("O dono padrão da zona é o `CKCurrentUserDefaultName` do CloudKit")
    func defaultOwnerNameMatchesCloudKit() {
        #expect(CloudZoneID.defaultOwnerName == CKCurrentUserDefaultName)
        #expect(CloudZoneID(name: Self.zoneName).ckZoneID.ownerName == CKCurrentUserDefaultName)
    }

    @Test(
        "A zona vai e volta sem trocar o dono, do lado do dono e do lado do convidado",
        arguments: [CKCurrentUserDefaultName, "_a1b2c3d4e5f6"])
    func zoneRoundTripKeepsOwner(owner: String) {
        let zone = CloudZoneID(name: Self.zoneName, ownerName: owner)
        #expect(zone.ckZoneID.zoneName == Self.zoneName)
        #expect(zone.ckZoneID.ownerName == owner)
        #expect(CloudZoneID(zone.ckZoneID) == zone)

        let ckZone = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: owner)
        #expect(CloudZoneID(ckZone).ckZoneID == ckZone)
        #expect(CloudZoneID(ckZone).ownerName == owner)
    }

    @Test("O mesmo registro em zonas de dono diferente continua sendo dois identificadores")
    func recordIDKeepsZoneOwner() {
        let owner = CloudRecordID(zone: CloudZoneID(name: Self.zoneName), name: "a")
        let guest = CloudRecordID(zone: CloudZoneID(name: Self.zoneName, ownerName: "_dono"), name: "a")
        #expect(owner != guest)
        #expect(CloudRecordID(owner.ckRecordID) == owner)
        #expect(CloudRecordID(guest.ckRecordID) == guest)
        #expect(owner.ckRecordID != guest.ckRecordID)
    }

    // MARK: Ida e volta de cada tipo de registro

    @Test(
        "Cartão com todos os campos: a ida e volta devolve os mesmos campos, tipo e nome, e o cartão lido é o mesmo",
        arguments: ItemKind.allCases)
    func cardRoundTrip(kind: ItemKind) throws {
        let item = SyncFixtures.fullItem(kind: kind)
        let record = try SyncFixtures.cardRecord(item, layer: 3.5)

        let back = try roundTrip(record)

        #expect(back.id == record.id)
        #expect(back.type == CloudSchema.RecordType.card.rawValue)
        #expect(back.fields == record.fields)
        #expect(try CardRecordMapping.card(from: back) == .card(SharedFieldPolicy.shared(item), layer: 3.5))
    }

    @Test("Texto livre, com e sem tamanho: a ida e volta devolve os mesmos campos e o mesmo texto", arguments: [true, false])
    func freeTextRoundTrip(withSize: Bool) throws {
        let text = BoardFreeText(
            id: UUID(), text: "Texto solto\ncom duas linhas", position: BoardPoint(x: -4.5, y: 90.25),
            createdAt: SyncFixtures.fractionalDate, size: withSize ? BoardSize(width: 320.5, height: 48.25) : nil)
        let record = SyncFixtures.record(.freeText, name: text.id.uuidString, fields: CardRecordMapping.fields(for: text))

        let back = try roundTrip(record)

        #expect(back.fields == record.fields)
        #expect(back.fields[CloudSchema.Key.width.rawValue] == (withSize ? .double(320.5) : nil))
        #expect(try CardRecordMapping.freeText(from: back) == .freeText(text))
    }

    @Test("Mural: o nome e a versão do formato vão e voltam, a versão como inteiro")
    func boardRoundTrip() throws {
        let fields = CardRecordMapping.boardFields(name: "Viagem à Lisboa", board: Board())
        let record = SyncFixtures.record(.mural, name: CloudSchema.muralRecordName, fields: fields)

        let back = try roundTrip(record)

        #expect(back.fields == fields)
        #expect(CardRecordMapping.boardName(from: back) == "Viagem à Lisboa")
        #expect(CardRecordMapping.boardFormatVersion(from: back) == Board().requiredFormatVersion)
    }

    @Test("Arquivo de mídia: o `CKAsset` aponta para o mesmo arquivo e o cartão dono volta")
    func mediaRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloudKitConversionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("AAAAAAAA-0000-4000-8000-000000000001.jpg")
        try Data([1, 2, 3]).write(to: file)
        let cardID = UUID()
        let record = SyncFixtures.record(
            .mediaFile, name: file.lastPathComponent, fields: CardRecordMapping.mediaFields(fileURL: file, cardID: cardID))

        let ck = try record.makeCKRecord()
        #expect((ck.object(forKey: CloudSchema.Key.file.rawValue) as? CKAsset)?.fileURL != nil)
        let back = try CloudRecord(ck)

        let media = try #require(CardRecordMapping.mediaFile(from: back))
        #expect(media.fileName == file.lastPathComponent)
        #expect(media.url.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
        #expect(CardRecordMapping.mediaCardID(from: back) == cardID)
    }

    @Test("Arquivo sem `fileURL` é erro de conversão")
    func assetWithoutFileIsAnError() {
        #expect(throws: CloudKitConversionError.assetWithoutFile(key: "file")) {
            try CloudValue.asset(fileURL: nil, key: "file")
        }
    }

    // MARK: Campos de sistema

    @Test(
        "Os campos de sistema sobrevivem à ida e volta: o registro desarquivado tem o mesmo nome, tipo e zona",
        arguments: [CKCurrentUserDefaultName, "_convidado"])
    func systemFieldsSurvive(owner: String) throws {
        let original = ckRecord(.card, owner: owner)
        set(original, "title", "Olá" as NSString)

        let cloud = try CloudRecord(original)
        #expect(cloud.systemFields != nil)
        #expect(cloud.id.zone.ownerName == owner)

        let again = try cloud.makeCKRecord()
        #expect(again.recordID == original.recordID)
        #expect(again.recordType == original.recordType)
        #expect(again.recordID.zoneID.ownerName == owner)
    }

    @Test("Sem campos de sistema o envio parte de um registro novo, com o mesmo nome e tipo")
    func recordWithoutSystemFieldsIsNew() throws {
        let record = SyncFixtures.record(.freeText, name: UUID().uuidString, fields: ["text": .string("a")])

        let ck = try record.makeCKRecord()

        #expect(ck.recordID == record.id.ckRecordID)
        #expect(ck.recordType == "FreeText")
        #expect(ck.recordChangeTag == nil)
        #expect(ck.changedKeys() == ["text"])
    }

    @Test("Campos de sistema ilegíveis são erro de conversão, não um registro novo")
    func invalidSystemFieldsAreAnError() {
        let record = CloudRecord(id: SyncFixtures.record(.card, name: "a", fields: [:]).id, type: "Card", systemFields: Data([1, 2, 3]))
        #expect(throws: CloudKitConversionError.invalidSystemFields) { try record.makeCKRecord() }
    }

    @Test("Um registro que nunca foi ao servidor não tem criador")
    func creatorIsNilForLocalRecord() throws {
        #expect(try CloudRecord(ckRecord()).creatorUserRecordName == nil)
    }

    // MARK: Chaves e tipos

    @Test("Chave desconhecida (de um app mais novo) é ignorada, e as conhecidas passam")
    func unknownKeyIsIgnored() throws {
        let record = ckRecord()
        set(record, "title", "Conhecido" as NSString)
        set(record, "campoDoAppNovo", "futuro" as NSString)
        set(record, "outroCampo", Date() as NSDate)

        #expect(try CloudRecord(record).fields == ["title": .string("Conhecido")])
    }

    @Test("Chave conhecida com tipo que o Mural não usa (data, referência, lista) é erro de conversão")
    func unsupportedTypeIsAnError() {
        let reference = CKRecord.Reference(recordID: ckRecord().recordID, action: .none)
        let values: [(key: String, value: any CKRecordValue)] = [
            ("x", Date() as NSDate), ("parentID", reference), ("tag", ["a", "b"] as NSArray),
        ]
        for (key, value) in values {
            let record = ckRecord()
            set(record, key, value)
            #expect(throws: CloudKitConversionError.unsupportedFieldType(key: key)) { try CloudRecord(record) }
        }
    }

    @Test("Número: a tabela de chaves decide entre inteiro e Double, não o valor")
    func numbersFollowTheKeyTable() throws {
        let record = ckRecord()
        set(record, "x", NSNumber(value: Int64(7)))
        set(record, "layer", NSNumber(value: 2))
        set(record, "createdAt", NSNumber(value: Int64(779_000_000)))
        set(record, "formatVersion", NSNumber(value: Int64(11)))

        let fields = try CloudRecord(record).fields

        #expect(fields["x"] == .double(7))
        #expect(fields["layer"] == .double(2))
        #expect(fields["createdAt"] == .double(779_000_000))
        #expect(fields["formatVersion"] == .int(11))
    }

    @Test("Inteiro guardado como Double volta inteiro; com parte fracionária o valor passa como veio")
    func integerKeyWithDouble() throws {
        let whole = ckRecord()
        set(whole, "formatVersion", NSNumber(value: 11.0))
        #expect(try CloudRecord(whole).fields["formatVersion"] == .int(11))

        let fractional = ckRecord()
        set(fractional, "formatVersion", NSNumber(value: 11.5))
        #expect(try CloudRecord(fractional).fields["formatVersion"] == .double(11.5))
    }

    @Test("Valor de tipo errado para a chave passa como veio, e quem o recusa é o mapeamento do cartão")
    func wrongTypeForKeyPassesThrough() throws {
        let record = try SyncFixtures.cardRecord(SyncFixtures.fullItem(kind: .sticky)).makeCKRecord()
        set(record, "x", "texto" as NSString)
        set(record, "title", NSNumber(value: Int64(5)))

        let cloud = try CloudRecord(record)

        #expect(cloud.fields["x"] == .string("texto"))
        #expect(cloud.fields["title"] == .int(5))
        #expect(throws: CardRecordMappingError.self) { try CardRecordMapping.card(from: cloud) }
    }

    // MARK: Campo removido

    @Test("Campo que o registro daqui perdeu é gravado como `nil`; os outros e as chaves de app mais novo ficam")
    func removedFieldBecomesNil() throws {
        let item = SyncFixtures.fullItem(kind: .sticky)
        let sent = try SyncFixtures.cardRecord(item)
        // O registro como o servidor o devolve: campos de sistema, os campos do cartão e uma chave de app mais novo.
        let server = try sent.makeCKRecord()
        set(server, "campoDoAppNovo", "futuro" as NSString)
        var cloud = try CloudRecord(server)
        cloud.fields["caption"] = nil
        cloud.fields["parentID"] = nil

        let resent = try cloud.makeCKRecord()

        #expect(resent.object(forKey: "caption") == nil)
        #expect(resent.object(forKey: "parentID") == nil)
        #expect(resent.changedKeys().contains("caption"))
        #expect(resent.changedKeys().contains("parentID"))
        #expect(!resent.changedKeys().contains("campoDoAppNovo"))
        #expect(resent.object(forKey: "title") as? String == item.title)
    }

    @Test("Registro novo não leva campos `nil`: não há o que apagar no servidor")
    func newRecordHasNoNilFields() throws {
        let record = SyncFixtures.record(.card, name: UUID().uuidString, fields: ["title": .string("a")])

        let ck = try record.makeCKRecord()

        #expect(ck.changedKeys() == ["title"])
    }

    @Test("As chaves de cada tipo de registro cobrem os campos que o mapeamento produz")
    func recordTypeKeysCoverTheMapping() throws {
        let allCardKeys = Set(try CardRecordMapping.fields(for: SyncFixtures.fullItem(kind: .sticky), layer: 1).keys)
        #expect(allCardKeys == Set(CloudSchema.RecordType.card.keys.map(\.rawValue)))

        let freeText = BoardFreeText(
            id: UUID(), text: "a", position: BoardPoint(x: 1, y: 2), createdAt: SyncFixtures.fractionalDate,
            size: BoardSize(width: 10, height: 20))
        #expect(Set(CardRecordMapping.fields(for: freeText).keys) == Set(CloudSchema.RecordType.freeText.keys.map(\.rawValue)))

        let board = CardRecordMapping.boardFields(name: "a", board: Board())
        #expect(Set(board.keys) == Set(CloudSchema.RecordType.mural.keys.map(\.rawValue)))

        let media = CardRecordMapping.mediaFields(fileURL: URL(filePath: "/tmp/a.jpg"), cardID: UUID())
        #expect(Set(media.keys) == Set(CloudSchema.RecordType.mediaFile.keys.map(\.rawValue)))
    }

    // MARK: Erros do CloudKit

    private func failure(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> SyncSaveFailure {
        let record = ckRecord()
        return CloudKitMapping.saveFailure(for: CKError(code, userInfo: userInfo), recordID: record.recordID)
    }

    @Test("Conflito de gravação: traz a versão do servidor, já convertida")
    func serverRecordChangedBecomesConflict() throws {
        let server = ckRecord(name: "11111111-2222-3333-4444-555555555555")
        set(server, "title", "do servidor" as NSString)

        let result = CloudKitMapping.saveFailure(
            for: CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server]), recordID: server.recordID)

        #expect(result == .conflict(serverRecord: try CloudRecord(server)))
    }

    @Test("Conflito cuja versão do servidor não converte, ou não veio, vira erro com a mensagem de registro ilegível")
    func unreadableServerRecordBecomesOther() {
        let server = ckRecord()
        set(server, "x", Date() as NSDate)
        let id = CloudRecordID(server.recordID)

        let unreadable = CloudKitMapping.saveFailure(
            for: CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server]), recordID: server.recordID)
        #expect(unreadable == .other(id, "registro do servidor ilegível"))

        let missing = CloudKitMapping.saveFailure(for: CKError(.serverRecordChanged), recordID: server.recordID)
        guard case .other(id, _) = missing else {
            Issue.record("esperava .other, veio \(missing)")
            return
        }
    }

    @Test("Os outros erros viram o caso correspondente do coordenador")
    func otherErrorsMapToCases() {
        let record = ckRecord()
        let id = CloudRecordID(record.recordID)
        let expected: [(CKError.Code, SyncSaveFailure)] = [
            (.unknownItem, .unknownItem(id)),
            (.zoneNotFound, .zoneMissing(id.zone)),
            (.userDeletedZone, .zoneMissing(id.zone)),
            (.quotaExceeded, .quotaExceeded(id)),
            (.permissionFailure, .permission(id)),
            (.networkFailure, .other(id, "erro do iCloud (código \(CKError.Code.networkFailure.rawValue))")),
            (.limitExceeded, .other(id, "erro do iCloud (código \(CKError.Code.limitExceeded.rawValue))")),
        ]
        for (code, failure) in expected {
            #expect(CloudKitMapping.saveFailure(for: CKError(code), recordID: record.recordID) == failure, "código \(code.rawValue)")
        }
    }

    @Test(
        "Motivo da zona apagada: no banco compartilhado é sempre acesso perdido; no privado, apagada ou dados apagados do iCloud",
        arguments: [
            (CloudDatabaseScope.shared, CKDatabase.DatabaseChange.Deletion.Reason.deleted, BoardRemovalReason.accessRevoked),
            (.shared, .purged, .accessRevoked),
            (.shared, .encryptedDataReset, .accessRevoked),
            (.private, .deleted, .zoneDeleted),
            (.private, .purged, .cloudDataErased),
            (.private, .encryptedDataReset, .cloudDataErased),
        ])
    func removalReasonByScope(
        scope: CloudDatabaseScope, reason: CKDatabase.DatabaseChange.Deletion.Reason, expected: BoardRemovalReason
    ) {
        #expect(CloudKitMapping.removalReason(for: reason, in: scope) == expected)
    }

    // MARK: Resultado de envio e de busca

    @Test("Envio: os aceitos levam os campos de sistema, apagar o que já não existe conta como apagado e as zonas são todas as do evento")
    func sendOutcomeTranslatesTheEvent() throws {
        let saved = ckRecord(name: "11111111-2222-3333-4444-555555555555")
        let failed = ckRecord(name: "22222222-2222-3333-4444-555555555555")
        let deleted = ckRecord(name: "33333333-2222-3333-4444-555555555555").recordID
        let gone = ckRecord(name: "44444444-2222-3333-4444-555555555555").recordID
        let refused = ckRecord(name: "55555555-2222-3333-4444-555555555555").recordID

        let outcome = CloudKitMapping.sendOutcome(
            savedRecords: [saved],
            failedSaves: [(failed, CKError(.quotaExceeded))],
            deletedRecordIDs: [deleted],
            failedDeletes: [gone: CKError(.unknownItem), refused: CKError(.permissionFailure)])

        #expect(outcome.saved == [try CloudRecord(saved)])
        #expect(outcome.saved.first?.systemFields != nil)
        #expect(outcome.deleted == [CloudRecordID(deleted), CloudRecordID(gone)])
        #expect(outcome.failures == [.quotaExceeded(CloudRecordID(failed.recordID)), .permission(CloudRecordID(refused))])
        #expect(outcome.zones == [CloudZoneID(name: Self.zoneName)])
        #expect(outcome.refused == [CloudRecordID(failed.recordID), CloudRecordID(refused)])
    }

    @Test("Envio: conflito, registro sumido e zona sumida não entram nos recusados, porque a próxima tentativa muda")
    func progressFailuresAreNotRefused() {
        let record = ckRecord()
        let server = ckRecord(name: record.recordID.recordName)

        let outcome = CloudKitMapping.sendOutcome(
            savedRecords: [],
            failedSaves: [
                (record, CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])),
                (ckRecord(), CKError(.unknownItem)),
                (ckRecord(), CKError(.zoneNotFound)),
            ],
            deletedRecordIDs: [],
            failedDeletes: [:])

        #expect(outcome.failures.count == 3)
        #expect(outcome.refused.isEmpty)
    }

    @Test("Envio: falha passageira não é recusa, não vai ao coordenador e fica fora das zonas, para continuar na fila do motor")
    func transientFailuresStayWithTheEngine() {
        let offline = ckRecord(name: "11111111-2222-3333-4444-555555555555")
        let busy = ckRecord(name: "22222222-2222-3333-4444-555555555555").recordID

        let outcome = CloudKitMapping.sendOutcome(
            savedRecords: [],
            failedSaves: [(offline, CKError(.networkUnavailable))],
            deletedRecordIDs: [],
            failedDeletes: [busy: CKError(.zoneBusy)])

        #expect(outcome.failures.isEmpty && outcome.refused.isEmpty && outcome.zones.isEmpty)
        #expect(outcome.retriedByEngine == [.save(CloudRecordID(offline.recordID)), .delete(CloudRecordID(busy))])
        for code in CloudKitMapping.transientErrorCodes {
            #expect(CloudKitMapping.isTransient(CKError(code)), "código \(code.rawValue)")
        }
        #expect(!CloudKitMapping.isTransient(CKError(.quotaExceeded)) && !CloudKitMapping.isTransient(CKError(.permissionFailure)))
    }

    @Test("Busca: o registro que não converte fica de fora da leva e os outros seguem; as zonas são as do que seguiu")
    func fetchOutcomeSkipsUnreadableRecords() throws {
        let good = ckRecord(name: "11111111-2222-3333-4444-555555555555")
        set(good, "title", "bom" as NSString)
        let bad = ckRecord(name: "22222222-2222-3333-4444-555555555555")
        set(bad, "x", Date() as NSDate)
        let removed = ckRecord(name: "33333333-2222-3333-4444-555555555555").recordID

        let outcome = CloudKitMapping.fetchOutcome(
            modifications: [bad, good], deletions: [(recordID: removed, recordType: CloudSchema.RecordType.card.rawValue)])

        #expect(outcome.saved == [try CloudRecord(good)])
        #expect(outcome.deleted == [CloudRecordID(removed)])
        #expect(outcome.zones == [CloudZoneID(name: Self.zoneName)])
    }

    @Test("Busca só com registros ilegíveis não declara nenhuma zona, para não apagar as pendências dela")
    func fetchOutcomeWithOnlyUnreadableRecordsHasNoZones() {
        let bad = ckRecord()
        set(bad, "x", Date() as NSDate)

        let outcome = CloudKitMapping.fetchOutcome(modifications: [bad], deletions: [])

        #expect(outcome.saved.isEmpty && outcome.deleted.isEmpty && outcome.zones.isEmpty)
    }

    // MARK: Convite

    /// O convite de uma zona, criado sem conta, só com o título. O CloudKit põe quem o cria como dono e como usuário atual, e esse
    /// único participante é o dono: sem o `participants` do resumo o dono não aparece.
    private func ckShare(title: String? = nil, owner: String = CKCurrentUserDefaultName) -> CKShare {
        let share = CKShare(recordZoneID: CKRecordZone.ID(zoneName: Self.zoneName, ownerName: owner))
        if let title { share[CKShare.SystemFieldKey.title] = title as NSString }
        return share
    }

    @Test("O convite da zona vai para os convites da leva, não para os registros, e o cartão da mesma leva segue normal")
    func shareIsSeparatedFromTheBoardRecords() throws {
        let card = ckRecord(name: "11111111-2222-3333-4444-555555555555")
        set(card, "title", "bom" as NSString)
        let share = ckShare(title: "Casa")
        #expect(share.recordType == CKRecord.SystemType.share)
        #expect(share.recordID.recordName == CKRecordNameZoneWideShare)

        let outcome = CloudKitMapping.fetchOutcome(modifications: [share, card], deletions: [])

        #expect(outcome.saved == [try CloudRecord(card)], "o convite não vira registro do mural, nem ilegível")
        #expect(outcome.deleted.isEmpty)
        #expect(outcome.shares == [ShareSummary(zone: CloudZoneID(name: Self.zoneName), title: "Casa", currentUserPermission: .owner)])
        #expect(outcome.zones == [CloudZoneID(name: Self.zoneName)], "só a zona do cartão: o convite não declara zona")
    }

    @Test("Só o convite na leva: nada segue para o coordenador, e nenhuma zona é declarada")
    func aBatchWithOnlyTheShareHasNothingForTheCoordinator() {
        let outcome = CloudKitMapping.fetchOutcome(modifications: [ckShare(title: "Casa")], deletions: [])

        #expect(outcome.saved.isEmpty && outcome.deleted.isEmpty && outcome.zones.isEmpty)
        #expect(outcome.shares.count == 1)
    }

    @Test("Convite sem título, e do lado do convidado: a zona leva o dono como veio")
    func shareKeepsTheZoneOwnerAndMissingTitle() {
        let outcome = CloudKitMapping.fetchOutcome(modifications: [ckShare(owner: "_dono")], deletions: [])

        #expect(outcome.shares == [ShareSummary(zone: CloudZoneID(name: Self.zoneName, ownerName: "_dono"), currentUserPermission: .owner)])
        #expect(outcome.shares.first?.title == nil && outcome.shares.first?.url == nil)
    }

    @Test("Registro de tipo de convite que não chega como CKShare sai da leva e não vira aviso nem resumo")
    func shareTypedRecordWithoutShareClassIsDropped() {
        let plain = CKRecord(
            recordType: CKRecord.SystemType.share,
            recordID: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: CKRecordZone.ID(zoneName: Self.zoneName)))

        let outcome = CloudKitMapping.fetchOutcome(modifications: [plain], deletions: [])

        #expect(outcome == CloudKitMapping.FetchOutcome())
    }

    @Test("Apagar o convite vira um resumo apagado da zona, e o apagamento de um registro do mural continua em `deleted`")
    func shareDeletionBecomesADeletedSummary() {
        let zone = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: "_dono")
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        let cardID = CKRecord.ID(recordName: "33333333-2222-3333-4444-555555555555", zoneID: zone)

        let outcome = CloudKitMapping.fetchOutcome(
            modifications: [],
            deletions: [(recordID: shareID, recordType: CKRecord.SystemType.share), (recordID: cardID, recordType: "Card")])

        #expect(outcome.shares == [ShareSummary(zone: CloudZoneID(zone), isDeleted: true)])
        #expect(outcome.deleted == [CloudRecordID(cardID)])
        #expect(outcome.zones == [CloudZoneID(zone)])
    }

    @Test("O apagamento do convite também é reconhecido pelo nome do registro, se o tipo vier vazio")
    func shareDeletionIsRecognizedByTheRecordName() {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: CKRecordZone.ID(zoneName: Self.zoneName))

        let outcome = CloudKitMapping.fetchOutcome(modifications: [], deletions: [(recordID: shareID, recordType: "")])

        #expect(outcome.shares == [ShareSummary(zone: CloudZoneID(name: Self.zoneName), isDeleted: true)])
        #expect(outcome.deleted.isEmpty)
    }

    @Test("Sem participante para o usuário atual a permissão é nil")
    func noCurrentParticipantMeansNoPermission() {
        #expect(CloudKitMapping.permission(of: nil) == nil)
    }

    @Test("Convite criado sem conta: quem o cria é o dono e o usuário atual, o nome do dono vem vazio e a lista de convidados não o inclui")
    func shareCreatedWithoutAnAccountListsNoGuests() {
        let share = ckShare(title: "Casa")
        #expect(share.participants.count == 1 && share.participants.first?.role == .owner, "o CloudKit lista o dono entre os participantes")

        let summary = ShareSummary(share)

        #expect(summary.currentUserPermission == .owner)
        #expect(summary.participants.isEmpty, "o dono fica de fora")
        #expect(summary.ownerDisplayName == nil, "componentes de nome vazios não viram nome")
        #expect(!summary.isDeleted)
    }

    @Test("Permissão do usuário atual: o dono vale como dono, o participante vale a permissão dele e sem permissão conhecida é nil")
    func currentUserPermissionFollowsRoleAndPermission() {
        let owner = CKShare.ParticipantRole.owner
        let guest = CKShare.ParticipantRole.privateUser
        let expected: [(CKShare.ParticipantRole, CKShare.ParticipantPermission, BoardCloudInfo.Permission?)] = [
            (owner, .readWrite, .owner), (owner, .unknown, .owner),
            (guest, .readWrite, .readWrite), (guest, .readOnly, .readOnly), (guest, .none, nil), (guest, .unknown, nil),
        ]
        for (role, permission, result) in expected {
            let mapped = CloudKitMapping.permission(role: role, permission: permission)
            #expect(mapped == result, "papel \(role.rawValue), permissão \(permission.rawValue)")
        }
    }

    @Test("Permissão do CloudKit para a do app: editar e ver passam, e sem permissão conhecida não há equivalente")
    func participantPermissionMapsToTheAppVocabulary() {
        #expect(BoardCloudInfo.Permission(CKShare.ParticipantPermission.readWrite) == .readWrite)
        #expect(BoardCloudInfo.Permission(CKShare.ParticipantPermission.readOnly) == .readOnly)
        #expect(BoardCloudInfo.Permission(CKShare.ParticipantPermission.none) == nil)
        #expect(BoardCloudInfo.Permission(CKShare.ParticipantPermission.unknown) == nil)
    }

    @Test("Nome para mostrar: sem componentes ou com componentes vazios é nil; com nome e sobrenome traz os dois")
    func displayNameFromNameComponents() {
        #expect(CloudKitMapping.displayName(from: nil) == nil)
        #expect(CloudKitMapping.displayName(from: PersonNameComponents()) == nil)

        var components = PersonNameComponents()
        components.givenName = "Ana"
        components.familyName = "Silva"
        let name = CloudKitMapping.displayName(from: components)
        #expect(name?.contains("Ana") == true && name?.contains("Silva") == true)
    }

    @Test("A pendência vai e volta entre o coordenador e o `CKSyncEngine`")
    func pendingChangeRoundTrip() {
        let id = CloudRecordID(zone: CloudZoneID(name: Self.zoneName, ownerName: "_dono"), name: UUID().uuidString)
        for change in [PendingChange.save(id), .delete(id)] {
            #expect(PendingChange(change.engineChange) == change)
        }
        #expect(PendingChange.save(id).engineChange == .saveRecord(id.ckRecordID))
        #expect(PendingChange.delete(id).engineChange == .deleteRecord(id.ckRecordID))
    }
}
