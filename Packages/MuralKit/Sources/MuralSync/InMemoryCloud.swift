import Foundation

/// Os erros do iCloud falso. Os dois últimos são a resposta de uma busca: o motor os traduz em `handleZoneDeleted`.
public enum InMemoryCloudError: Error, Equatable, Sendable {
    /// Gerenciar uma zona que não existe (criar convite, por exemplo).
    case zoneNotFound(String)
    /// A zona não existe mais (o dono a apagou).
    case zoneDeleted(CloudZoneID)
    /// A zona existe, mas esta pessoa já não tem acesso a ela (o dono tirou o convite).
    case accessRevoked(CloudZoneID)
}

/// O iCloud em memória dos testes: zonas com registros, convites e um registro de mudanças por zona, sem CloudKit e sem rede.
///
/// As regras de servidor imitam o CloudKit, para que a conta de sincronização rode contra o que o iCloud de verdade faz:
/// - Gravar exige que `CloudRecord.systemFields` traga a marca atual do registro. Marca diferente é `.conflict` com a versão do
///   servidor, registro novo (sem marca) que já existe também é `.conflict`, e marca de um registro que já não existe é
///   `.unknownItem`.
/// - Zona inexistente, ou a que a pessoa não pode mais acessar, é `.zoneMissing`; quem só pode ver recebe `.permission`.
/// - Apagar não confere marca, e apagar o que não existe conta como apagado.
/// - Cada registro é tratado por si, como no CloudKit sem lote atômico: num mesmo envio uns passam e outros são recusados.
/// - O servidor preenche `creatorUserRecordName` na criação e o mantém nas gravações seguintes.
///
/// Cada zona existe uma vez, mas o `CloudZoneID` que cada pessoa vê muda, como no CloudKit: o dono a vê com
/// `CloudZoneID.defaultOwnerName` e o convidado com o nome do dono. Os registros que voltam a cada pessoa trazem a zona como ela a
/// vê. Pessoas são nomes de texto, sem conta.
///
/// Os arquivos (`CloudValue.asset`) são copiados para uma pasta temporária do iCloud falso ao gravar, e quem busca recebe o endereço
/// da cópia, como o `CKAsset`. A pasta some junto com o objeto.
public actor InMemoryCloud {
    /// O que o dono permite a um convidado.
    public enum GuestPermission: Equatable, Sendable {
        case readWrite
        case readOnly
    }

    /// O que uma busca devolve: o estado atual dos registros que mudaram, os apagados e o contador novo da zona.
    public struct FetchedChanges: Equatable, Sendable {
        public var saved: [CloudRecord]
        public var deleted: [CloudRecordID]
        /// O contador da zona depois destas mudanças; a próxima busca o passa em `since`.
        public var token: Int

        public init(saved: [CloudRecord] = [], deleted: [CloudRecordID] = [], token: Int = 0) {
            self.saved = saved
            self.deleted = deleted
            self.token = token
        }
    }

    /// O resultado de um envio: o que o servidor aceitou (com os campos de sistema dele) e o que recusou.
    public struct SendResult: Equatable, Sendable {
        public var saved: [CloudRecord]
        public var deleted: [CloudRecordID]
        public var failures: [SyncSaveFailure]

        public init(saved: [CloudRecord] = [], deleted: [CloudRecordID] = [], failures: [SyncSaveFailure] = []) {
            self.saved = saved
            self.deleted = deleted
            self.failures = failures
        }
    }

    private struct ZoneKey: Hashable {
        var owner: String
        var name: String
    }

    private struct StoredRecord {
        var type: String
        var fields: [String: CloudValue]
        var creator: String
        /// O contador da zona na última gravação: serve de marca de alteração e de ponto de corte das buscas.
        var mark: Int
    }

    private struct Zone {
        /// Sobe a cada gravação ou apagamento aceitos.
        var counter = 0
        var records: [String: StoredRecord] = [:]
        /// O contador em que cada registro foi apagado, para as buscas contarem o apagamento.
        var deletions: [String: Int] = [:]
        var guests: [String: GuestPermission] = [:]
    }

    /// O que a pessoa pode fazer numa zona.
    private enum Access {
        case missing
        case noAccess
        case owner
        case guest(GuestPermission)
    }

    private var zones: [ZoneKey: Zone] = [:]
    private var refusedSaves = Set<String>()
    private var refusedDeletes = Set<String>()
    private var assetCount = 0
    private let storage: URL

    public init() {
        storage = FileManager.default.temporaryDirectory.appendingPathComponent("InMemoryCloud-\(UUID().uuidString)", isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: storage)
    }

    // MARK: Zonas e convites

    /// Cria a zona do dono. Não faz nada se ela já existe.
    public func createZone(_ name: String, owner: String) {
        let key = ZoneKey(owner: owner, name: name)
        if zones[key] == nil { zones[key] = Zone() }
    }

    /// Dá acesso a `user`, ou troca a permissão que ele tinha.
    /// - Throws: `InMemoryCloudError.zoneNotFound` se a zona não existe.
    public func share(zone name: String, owner: String, with user: String, permission: GuestPermission) throws {
        let key = ZoneKey(owner: owner, name: name)
        guard zones[key] != nil else { throw InMemoryCloudError.zoneNotFound(name) }
        zones[key]?.guests[user] = permission
    }

    /// Tira o acesso de `user`: a zona continua para o dono e os outros convidados.
    /// - Throws: `InMemoryCloudError.zoneNotFound` se a zona não existe.
    public func revoke(zone name: String, owner: String, from user: String) throws {
        let key = ZoneKey(owner: owner, name: name)
        guard zones[key] != nil else { throw InMemoryCloudError.zoneNotFound(name) }
        zones[key]?.guests[user] = nil
    }

    /// Apaga a zona com tudo o que há nela, para o dono e para os convidados.
    public func deleteZone(_ name: String, owner: String) {
        zones[ZoneKey(owner: owner, name: name)] = nil
    }

    /// As zonas que a pessoa vê em um banco, em ordem fixa, como ela as vê: no banco privado, as dela, com o dono padrão; no
    /// compartilhado, as que outras pessoas deram a ela, com o nome do dono.
    public func zones(for user: String, scope: CloudDatabaseScope) -> [CloudZoneID] {
        let visible: [CloudZoneID]
        switch scope {
        case .private:
            visible = zones.keys.filter { $0.owner == user }.map { CloudZoneID(name: $0.name) }
        case .shared:
            visible = zones.filter { $0.key.owner != user && $0.value.guests[user] != nil }
                .map { CloudZoneID(name: $0.key.name, ownerName: $0.key.owner) }
        }
        return visible.sorted { ($0.ownerName, $0.name) < ($1.ownerName, $1.name) }
    }

    /// O que o dono permitiu a `user` na zona, ou `nil` se `user` não é convidado dela ou a zona não existe. No CloudKit de verdade
    /// essa permissão só chega com o convite; aqui ela é consultada para o motor corrigir a de uma zona que acabou de adotar.
    public func guestPermission(of user: String, inZone name: String, owner: String) -> GuestPermission? {
        zones[ZoneKey(owner: owner, name: name)]?.guests[user]
    }

    // MARK: Enviar

    /// Grava e apaga registros em nome de `user`, um por um, com as regras do tipo. A zona de cada registro é a que `user` vê.
    public func send(saving records: [CloudRecord], deleting ids: [CloudRecordID], as user: String) -> SendResult {
        var result = SendResult()
        for record in records { save(record, as: user, into: &result) }
        for id in ids { delete(id, as: user, into: &result) }
        return result
    }

    /// A próxima gravação de um registro com este nome é recusada com `.other(id, "falha injetada")`, uma vez só: para provar um
    /// envio confirmado só em parte.
    public func refuseNextSave(of recordName: String) {
        refusedSaves.insert(recordName)
    }

    /// Como `refuseNextSave(of:)`, para o apagamento.
    public func refuseNextDelete(of recordName: String) {
        refusedDeletes.insert(recordName)
    }

    // MARK: Buscar

    /// O que mudou na zona desde `token`, como `user` vê a zona. O estado dos registros é o atual, na ordem em que mudaram, e os
    /// apagados vêm à parte. Com `token` 0 (primeira busca) não há apagamentos: quem nunca viu o registro não precisa saber que
    /// ele sumiu.
    /// - Throws: `InMemoryCloudError.zoneDeleted` se a zona não existe, `.accessRevoked` se existe mas `user` não a acessa mais.
    public func fetchChanges(zone: CloudZoneID, since token: Int, as user: String) throws -> FetchedChanges {
        let (key, access) = resolve(zone, as: user)
        switch access {
        case .missing: throw InMemoryCloudError.zoneDeleted(zone)
        case .noAccess: throw InMemoryCloudError.accessRevoked(zone)
        case .owner, .guest: break
        }
        guard let stored = zones[key] else { throw InMemoryCloudError.zoneDeleted(zone) }
        let saved = stored.records.filter { $0.value.mark > token }
            .sorted { ($0.value.mark, $0.key) < ($1.value.mark, $1.key) }
            .map { serverRecord(named: $0.key, $0.value, in: key, as: user) }
        let deleted =
            token == 0
            ? []
            : stored.deletions.filter { $0.value > token }
                .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
                .map { CloudRecordID(zone: view(of: key, as: user), name: $0.key) }
        return FetchedChanges(saved: saved, deleted: deleted, token: stored.counter)
    }

    // MARK: Para os testes

    /// Todos os registros da zona, por nome, como o dono os vê. Vazio se a zona não existe.
    public func records(inZone name: String, owner: String) -> [CloudRecord] {
        let key = ZoneKey(owner: owner, name: name)
        guard let zone = zones[key] else { return [] }
        return zone.records.sorted { $0.key < $1.key }.map { serverRecord(named: $0.key, $0.value, in: key, as: owner) }
    }

    /// O contador de mudanças da zona, ou `nil` se ela não existe.
    public func changeCounter(inZone name: String, owner: String) -> Int? {
        zones[ZoneKey(owner: owner, name: name)]?.counter
    }

    // MARK: Interno

    private func save(_ record: CloudRecord, as user: String, into result: inout SendResult) {
        let (key, access) = resolve(record.id.zone, as: user)
        switch access {
        case .missing, .noAccess:
            result.failures.append(.zoneMissing(record.id.zone))
            return
        case .guest(.readOnly):
            result.failures.append(.permission(record.id))
            return
        case .owner, .guest(.readWrite):
            break
        }
        guard var zone = zones[key] else { return }
        if refusedSaves.remove(record.id.name) != nil {
            result.failures.append(.other(record.id, "falha injetada"))
            return
        }

        let existing = zone.records[record.id.name]
        if let existing {
            guard let sent = record.systemFields, Self.mark(in: sent) == existing.mark else {
                result.failures.append(.conflict(serverRecord: serverRecord(named: record.id.name, existing, in: key, as: user)))
                return
            }
        } else if record.systemFields != nil {
            result.failures.append(.unknownItem(record.id))
            return
        }

        let fields: [String: CloudValue]
        do {
            fields = try storeAssets(in: record.fields)
        } catch {
            result.failures.append(.other(record.id, "arquivo ilegível: \(error.localizedDescription)"))
            return
        }
        zone.counter += 1
        let stored = StoredRecord(type: record.type, fields: fields, creator: existing?.creator ?? user, mark: zone.counter)
        zone.records[record.id.name] = stored
        zone.deletions[record.id.name] = nil
        zones[key] = zone
        result.saved.append(serverRecord(named: record.id.name, stored, in: key, as: user))
    }

    private func delete(_ id: CloudRecordID, as user: String, into result: inout SendResult) {
        let (key, access) = resolve(id.zone, as: user)
        switch access {
        case .missing, .noAccess:
            result.failures.append(.zoneMissing(id.zone))
            return
        case .guest(.readOnly):
            result.failures.append(.permission(id))
            return
        case .owner, .guest(.readWrite):
            break
        }
        guard var zone = zones[key] else { return }
        if refusedDeletes.remove(id.name) != nil {
            result.failures.append(.other(id, "falha injetada"))
            return
        }
        if zone.records.removeValue(forKey: id.name) != nil {
            zone.counter += 1
            zone.deletions[id.name] = zone.counter
            zones[key] = zone
        }
        result.deleted.append(id)
    }

    /// A zona verdadeira e o que `user` pode fazer nela. Quem usa o dono padrão fala da própria zona.
    private func resolve(_ zone: CloudZoneID, as user: String) -> (ZoneKey, Access) {
        let owner = zone.ownerName == CloudZoneID.defaultOwnerName ? user : zone.ownerName
        let key = ZoneKey(owner: owner, name: zone.name)
        guard let stored = zones[key] else { return (key, .missing) }
        if owner == user { return (key, .owner) }
        guard let permission = stored.guests[user] else { return (key, .noAccess) }
        return (key, .guest(permission))
    }

    /// A zona como `user` a vê: o dono a vê com o dono padrão, os outros com o nome do dono.
    private func view(of key: ZoneKey, as user: String) -> CloudZoneID {
        CloudZoneID(name: key.name, ownerName: key.owner == user ? CloudZoneID.defaultOwnerName : key.owner)
    }

    private func serverRecord(named name: String, _ stored: StoredRecord, in key: ZoneKey, as user: String) -> CloudRecord {
        CloudRecord(
            id: CloudRecordID(zone: view(of: key, as: user), name: name), type: stored.type, fields: stored.fields,
            creatorUserRecordName: stored.creator, systemFields: Self.data(forMark: stored.mark))
    }

    /// Copia cada arquivo para a pasta do iCloud falso, para que mudar ou apagar o original não mude o que o servidor guarda.
    private func storeAssets(in fields: [String: CloudValue]) throws -> [String: CloudValue] {
        var stored = fields
        for (name, value) in fields {
            guard case .asset(let url) = value else { continue }
            assetCount += 1
            let directory = storage.appendingPathComponent(String(assetCount), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appendingPathComponent(url.lastPathComponent, isDirectory: false)
            try FileManager.default.copyItem(at: url, to: copy)
            stored[name] = .asset(copy)
        }
        return stored
    }

    /// A marca guardada como os 8 bytes de um inteiro.
    private static func data(forMark mark: Int) -> Data {
        withUnsafeBytes(of: UInt64(mark).bigEndian) { Data($0) }
    }

    /// O inteiro de uma marca, ou `nil` se os bytes não são os de uma marca.
    private static func mark(in data: Data) -> Int? {
        guard data.count == MemoryLayout<UInt64>.size else { return nil }
        return Int(exactly: data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
    }
}
