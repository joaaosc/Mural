import Foundation
import MuralKit
import MuralSync
import Testing

@Suite("iCloud falso: as regras de servidor que imitam o CloudKit")
struct InMemoryCloudTests {
    private static let zoneName = "mural-5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01"
    private static let ownerView = CloudZoneID(name: zoneName)
    private static let guestView = CloudZoneID(name: zoneName, ownerName: "ana")

    /// Um iCloud com a zona de "ana" compartilhada com "bia" (leitura e escrita) e "caio" (só leitura).
    private func makeCloud() async throws -> InMemoryCloud {
        let cloud = InMemoryCloud()
        await cloud.createZone(Self.zoneName, owner: "ana")
        try await cloud.share(zone: Self.zoneName, owner: "ana", with: "bia", permission: .readWrite)
        try await cloud.share(zone: Self.zoneName, owner: "ana", with: "caio", permission: .readOnly)
        return cloud
    }

    private func record(
        _ name: String, text: String = "Texto", in zone: CloudZoneID = ownerView, marks: Data? = nil, type: String = "Card"
    ) -> CloudRecord {
        CloudRecord(id: CloudRecordID(zone: zone, name: name), type: type, fields: ["text": .string(text)], systemFields: marks)
    }

    private func id(_ name: String, in zone: CloudZoneID = ownerView) -> CloudRecordID {
        CloudRecordID(zone: zone, name: name)
    }

    @Test("Cada pessoa vê a zona do seu jeito: o dono com o dono padrão e o convidado com o nome do dono, também nos registros")
    func zonesAreSeenFromEachSide() async throws {
        let cloud = try await makeCloud()
        let created = await cloud.send(saving: [record("a")], deleting: [], as: "ana")
        #expect(created.saved.first?.id.zone == Self.ownerView)

        let ownerFetch = try await cloud.fetchChanges(zone: Self.ownerView, since: 0, as: "ana")
        let guestFetch = try await cloud.fetchChanges(zone: Self.guestView, since: 0, as: "bia")
        #expect(ownerFetch.saved.map(\.id.zone) == [Self.ownerView])
        #expect(guestFetch.saved.map(\.id.zone) == [Self.guestView])
        #expect(await cloud.zones(for: "ana", scope: .private) == [Self.ownerView])
        #expect(await cloud.zones(for: "ana", scope: .shared).isEmpty)
        #expect(await cloud.zones(for: "bia", scope: .shared) == [Self.guestView])
        #expect(await cloud.zones(for: "bia", scope: .private).isEmpty)

        let sentByGuest = await cloud.send(saving: [record("b", in: Self.guestView)], deleting: [], as: "bia")
        #expect(sentByGuest.saved.first?.id.zone == Self.guestView)
        #expect(await cloud.records(inZone: Self.zoneName, owner: "ana").map(\.id.zone) == [Self.ownerView, Self.ownerView])
    }

    @Test("O servidor dá a marca (8 bytes de um inteiro) e o criador na criação, e mantém o criador nas gravações seguintes")
    func marksAndCreator() async throws {
        let cloud = try await makeCloud()
        let first = try #require(await cloud.send(saving: [record("a", in: Self.guestView)], deleting: [], as: "bia").saved.first)
        #expect(first.creatorUserRecordName == "bia")
        #expect(first.systemFields?.count == 8)

        let second = try #require(
            await cloud.send(saving: [record("a", text: "Novo", marks: first.systemFields)], deleting: [], as: "ana").saved.first)
        #expect(second.creatorUserRecordName == "bia", "o criador não muda ao regravar")
        #expect(second.systemFields != first.systemFields)
        #expect(second.fields["text"] == .string("Novo"))
    }

    @Test("Marca diferente ou registro novo que já existe dá conflito com a versão do servidor; marca de registro que sumiu dá unknownItem")
    func conflictsAndUnknownItems() async throws {
        let cloud = try await makeCloud()
        let first = try #require(await cloud.send(saving: [record("a", text: "Servidor")], deleting: [], as: "ana").saved.first)

        let stale = record("a", text: "Velho", in: Self.guestView, marks: Data(repeating: 0, count: 8))
        let fresh = record("a", text: "Novo, sem marca", in: Self.guestView)
        let result = await cloud.send(saving: [stale, fresh], deleting: [], as: "bia")
        #expect(result.saved.isEmpty)
        // A versão do servidor volta com a zona como a convidada a vê.
        let serverView = CloudRecord(
            id: id("a", in: Self.guestView), type: first.type, fields: first.fields, creatorUserRecordName: "ana",
            systemFields: first.systemFields)
        #expect(result.failures == [.conflict(serverRecord: serverView), .conflict(serverRecord: serverView)])

        _ = await cloud.send(saving: [], deleting: [id("a")], as: "ana")
        let gone = await cloud.send(saving: [record("a", marks: first.systemFields)], deleting: [], as: "ana")
        #expect(gone.failures == [.unknownItem(id("a"))])
        #expect(await cloud.records(inZone: Self.zoneName, owner: "ana").isEmpty)
    }

    @Test("Zona inexistente ou sem acesso dá zoneMissing, e quem só pode ver recebe permission, em gravar e em apagar")
    func zoneAndPermissionFailures() async throws {
        let cloud = try await makeCloud()
        let other = CloudZoneID(name: "mural-00000000-0000-4000-8000-000000000000")
        let missing = await cloud.send(saving: [record("a", in: other)], deleting: [id("b", in: other)], as: "ana")
        #expect(missing.failures == [.zoneMissing(other), .zoneMissing(other)])

        let stranger = await cloud.send(saving: [record("a", in: Self.guestView)], deleting: [], as: "dora")
        #expect(stranger.failures == [.zoneMissing(Self.guestView)])

        let readOnly = await cloud.send(
            saving: [record("a", in: Self.guestView)], deleting: [id("b", in: Self.guestView)], as: "caio")
        #expect(readOnly.failures == [.permission(id("a", in: Self.guestView)), .permission(id("b", in: Self.guestView))])
        #expect(await cloud.records(inZone: Self.zoneName, owner: "ana").isEmpty)
        #expect(await cloud.changeCounter(inZone: Self.zoneName, owner: "ana") == 0)
    }

    @Test("Apagar não confere marca e apagar o que não existe conta como apagado")
    func deletesIgnoreMarksAndMissingRecords() async throws {
        let cloud = try await makeCloud()
        _ = await cloud.send(saving: [record("a")], deleting: [], as: "ana")
        let counter = try #require(await cloud.changeCounter(inZone: Self.zoneName, owner: "ana"))

        let ids = [id("a", in: Self.guestView), id("nunca-existiu", in: Self.guestView)]
        let result = await cloud.send(saving: [], deleting: ids, as: "bia")
        #expect(result.deleted == ids && result.failures.isEmpty)
        #expect(await cloud.records(inZone: Self.zoneName, owner: "ana").isEmpty)
        #expect(await cloud.changeCounter(inZone: Self.zoneName, owner: "ana") == counter + 1, "só o que existia entra no registro")
    }

    @Test("A busca traz o estado atual dos registros mudados e os apagados desde o contador, e o contador novo")
    func fetchReturnsChangesSinceTheToken() async throws {
        let cloud = try await makeCloud()
        _ = await cloud.send(saving: [record("a"), record("b")], deleting: [], as: "ana")
        let first = try await cloud.fetchChanges(zone: Self.ownerView, since: 0, as: "ana")
        #expect(first.saved.map(\.id.name) == ["a", "b"] && first.deleted.isEmpty)

        let current = try #require(first.saved.first { $0.id.name == "a" })
        _ = await cloud.send(saving: [record("a", text: "Mudou", marks: current.systemFields)], deleting: [id("b")], as: "ana")
        let second = try await cloud.fetchChanges(zone: Self.ownerView, since: first.token, as: "ana")
        #expect(second.saved.map(\.id.name) == ["a"] && second.saved.first?.fields["text"] == .string("Mudou"))
        #expect(second.deleted == [id("b")])
        #expect(second.token > first.token)

        let idle = try await cloud.fetchChanges(zone: Self.ownerView, since: second.token, as: "ana")
        #expect(idle.saved.isEmpty && idle.deleted.isEmpty && idle.token == second.token)

        let fromScratch = try await cloud.fetchChanges(zone: Self.guestView, since: 0, as: "bia")
        #expect(fromScratch.saved.map(\.id.name) == ["a"] && fromScratch.deleted.isEmpty, "quem nunca viu o registro não vê o apagamento")
    }

    @Test("Zona apagada e acesso retirado dão erros diferentes na busca; quem perdeu o acesso deixa de ver a zona")
    func fetchReportsDeletedZonesAndRevokedAccess() async throws {
        let cloud = try await makeCloud()
        try await cloud.revoke(zone: Self.zoneName, owner: "ana", from: "bia")
        await #expect(throws: InMemoryCloudError.accessRevoked(Self.guestView)) {
            _ = try await cloud.fetchChanges(zone: Self.guestView, since: 0, as: "bia")
        }
        #expect(await cloud.zones(for: "bia", scope: .shared).isEmpty)
        _ = try await cloud.fetchChanges(zone: Self.guestView, since: 0, as: "caio")

        await cloud.deleteZone(Self.zoneName, owner: "ana")
        await #expect(throws: InMemoryCloudError.zoneDeleted(Self.guestView)) {
            _ = try await cloud.fetchChanges(zone: Self.guestView, since: 0, as: "caio")
        }
        await #expect(throws: InMemoryCloudError.zoneDeleted(Self.ownerView)) {
            _ = try await cloud.fetchChanges(zone: Self.ownerView, since: 0, as: "ana")
        }
        await #expect(throws: InMemoryCloudError.zoneNotFound(Self.zoneName)) {
            try await cloud.share(zone: Self.zoneName, owner: "ana", with: "bia", permission: .readWrite)
        }
    }

    @Test("A recusa injetada vale uma vez só e o resto do lote passa: cada registro é tratado por si")
    func injectedRefusalsAreOneShotAndPerRecord() async throws {
        let cloud = try await makeCloud()
        await cloud.refuseNextSave(of: "b")
        let first = await cloud.send(saving: [record("a"), record("b"), record("c")], deleting: [], as: "ana")
        #expect(first.saved.map(\.id.name) == ["a", "c"])
        #expect(first.failures == [.other(id("b"), "falha injetada")])

        let second = await cloud.send(saving: [record("b")], deleting: [], as: "ana")
        #expect(second.saved.map(\.id.name) == ["b"] && second.failures.isEmpty)

        await cloud.refuseNextDelete(of: "a")
        let deletes = await cloud.send(saving: [], deleting: [id("a"), id("c")], as: "ana")
        #expect(deletes.deleted == [id("c")] && deletes.failures == [.other(id("a"), "falha injetada")])
        let retry = await cloud.send(saving: [], deleting: [id("a")], as: "ana")
        #expect(retry.deleted == [id("a")] && retry.failures.isEmpty)
    }

    @Test("O arquivo é copiado ao gravar: mudar ou apagar o original não muda o que o servidor guarda")
    func assetsAreCopiedOnSave() async throws {
        let cloud = try await makeCloud()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InMemoryCloudTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("foto.jpg")
        try Data("bytes".utf8).write(to: original)

        let media = CloudRecord(id: id("foto.jpg"), type: "MediaFile", fields: ["file": .asset(original)])
        let saved = try #require(await cloud.send(saving: [media], deleting: [], as: "ana").saved.first)
        try FileManager.default.removeItem(at: original)

        let fetched = try await cloud.fetchChanges(zone: Self.guestView, since: 0, as: "bia")
        guard case .asset(let url)? = fetched.saved.first?.fields["file"], case .asset(let savedURL)? = saved.fields["file"] else {
            Issue.record("o registro não traz o arquivo")
            return
        }
        #expect(url == savedURL && url != original)
        #expect(try Data(contentsOf: url) == Data("bytes".utf8))

        let missing = CloudRecord(id: id("sumiu.jpg"), type: "MediaFile", fields: ["file": .asset(original)])
        let failed = await cloud.send(saving: [missing], deleting: [], as: "ana")
        #expect(failed.saved.isEmpty && failed.failures.count == 1)
    }
}
