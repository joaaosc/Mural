import Foundation
import MuralKit

/// Em qual banco do iCloud: o privado da própria pessoa ou o compartilhado com ela.
public enum CloudDatabaseScope: String, Codable, Sendable {
    case `private`
    case shared
}

/// O que este Mac sabe de um mural no iCloud.
///
/// É o que permite a junção (`BoardMerge`) e a conta do que falta enviar: sem a `base`, não há como saber o que mudou aqui e o que
/// mudou lá. No disco, os conjuntos vão em lista ordenada e as camadas em objeto de chave UUID, então o mesmo estado dá sempre os
/// mesmos bytes (um `Set` ou um dicionário de chave não textual sairiam em ordem diferente a cada execução).
public struct BoardSyncState: Codable, Equatable, Sendable {
    public var cloud: BoardCloudInfo
    /// O mural como o iCloud o tem (cartões na forma `SharedFieldPolicy.shared`): base da junção e da conta do que falta enviar.
    public var base: Board
    /// O nome do mural como está no iCloud; nil antes do primeiro envio.
    public var baseName: String?
    /// A versão do formato que o registro do mural tem no iCloud; nil antes do primeiro envio. Fica à parte porque a base só mostra a
    /// versão que o conteúdo exige: se os cartões forem aceitos e o registro do mural não, o iCloud segue com a versão antiga e o
    /// mural continua pendente.
    public var baseBoardFormatVersion: Int?
    /// O número de empilhamento de cada cartão como está no iCloud.
    public var layers: [UUID: Double]
    /// Campos de sistema de cada registro pelo nome (opacos aqui: o motor de verdade guarda o arquivamento do `CKRecord`).
    public var systemFields: [String: Data]
    /// Arquivos de `Items/` que já estão no iCloud.
    public var uploadedFiles: Set<String>
    /// O cartão a que cada arquivo de `uploadedFiles` pertence (o campo `cardID` do registro), pelo nome do arquivo. Só entra um dono
    /// que este Mac conhece. Com ele o arquivo sai do iCloud mesmo depois de o cartão já ter saído da base, e o arquivo de um cartão de
    /// app mais novo (`unsupportedRecordNames`) nunca sai.
    public var mediaOwners: [String: UUID]
    /// Registros de um app mais novo, que este Mac não entende e nunca apaga nem regrava.
    public var unsupportedRecordNames: Set<String>
    /// O que chegou do iCloud não pôde ser gravado neste Mac: o estado ficou o de antes (o que combina com o disco) e a zona precisa
    /// ser buscada de novo inteira, porque o motor já passou daquelas mudanças. Só vai ao disco quando ligado.
    public var needsFullFetch: Bool
    /// O mural foi adotado do iCloud (a zona é nova neste Mac) e a primeira busca completa ainda não terminou: o pacote local é
    /// provisório, vazio e com um nome que não é o do mural. Enquanto ligado, nada é enviado (`SyncCore.pendingChanges` e
    /// `SyncCore.record(for:state:local:name:itemsDirectory:)`), senão o nome provisório subiria ao iCloud e renomearia o mural de
    /// todos. Só vai ao disco quando ligado.
    public var isAwaitingFirstFetch: Bool
    /// O mural veio de uma zona que outro Mac criou (adotado). Este Mac nunca cria o registro do mural, só o regrava depois de
    /// recebê-lo (`baseName != nil`): se a zona ainda não tem o registro (o dono no meio do primeiro envio), a primeira busca termina
    /// sem nome, e criá-lo aqui subiria o nome provisório e renomearia o mural de todos. Só vai ao disco quando ligado.
    public var isAdopted: Bool

    public init(
        cloud: BoardCloudInfo,
        base: Board = Board(),
        baseName: String? = nil,
        baseBoardFormatVersion: Int? = nil,
        layers: [UUID: Double] = [:],
        systemFields: [String: Data] = [:],
        uploadedFiles: Set<String> = [],
        mediaOwners: [String: UUID] = [:],
        unsupportedRecordNames: Set<String> = [],
        needsFullFetch: Bool = false,
        isAwaitingFirstFetch: Bool = false,
        isAdopted: Bool = false
    ) {
        self.cloud = cloud
        self.base = base
        self.baseName = baseName
        self.baseBoardFormatVersion = baseBoardFormatVersion
        self.layers = layers
        self.systemFields = systemFields
        self.uploadedFiles = uploadedFiles
        self.mediaOwners = mediaOwners
        self.unsupportedRecordNames = unsupportedRecordNames
        self.needsFullFetch = needsFullFetch
        self.isAwaitingFirstFetch = isAwaitingFirstFetch
        self.isAdopted = isAdopted
    }

    private enum CodingKeys: String, CodingKey {
        case cloud, base, baseName, baseBoardFormatVersion, layers, systemFields, uploadedFiles, mediaOwners, unsupportedRecordNames
        case needsFullFetch, isAwaitingFirstFetch, isAdopted
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cloud = try container.decode(BoardCloudInfo.self, forKey: .cloud)
        base = try container.decode(Board.self, forKey: .base)
        baseName = try container.decodeIfPresent(String.self, forKey: .baseName)
        // Os dois campos novos faltam nos estados gravados antes deles: ausentes valem nil e vazio.
        baseBoardFormatVersion = try container.decodeIfPresent(Int.self, forKey: .baseBoardFormatVersion)
        mediaOwners = try container.decodeIfPresent([String: UUID].self, forKey: .mediaOwners) ?? [:]
        var layers: [UUID: Double] = [:]
        for (name, layer) in try container.decode([String: Double].self, forKey: .layers) {
            // Duas chaves para o mesmo UUID (maiúsculas e minúsculas) só existem em arquivo mexido à mão.
            guard let id = UUID(uuidString: name), layers.updateValue(layer, forKey: id) == nil else {
                throw DecodingError.dataCorruptedError(
                    forKey: .layers, in: container, debugDescription: "a chave \(name) não é um UUID único")
            }
        }
        self.layers = layers
        systemFields = try container.decode([String: Data].self, forKey: .systemFields)
        uploadedFiles = Set(try container.decode([String].self, forKey: .uploadedFiles))
        unsupportedRecordNames = Set(try container.decode([String].self, forKey: .unsupportedRecordNames))
        needsFullFetch = try container.decodeIfPresent(Bool.self, forKey: .needsFullFetch) ?? false
        isAwaitingFirstFetch = try container.decodeIfPresent(Bool.self, forKey: .isAwaitingFirstFetch) ?? false
        isAdopted = try container.decodeIfPresent(Bool.self, forKey: .isAdopted) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cloud, forKey: .cloud)
        try container.encode(base, forKey: .base)
        try container.encodeIfPresent(baseName, forKey: .baseName)
        try container.encodeIfPresent(baseBoardFormatVersion, forKey: .baseBoardFormatVersion)
        try container.encode(Dictionary(uniqueKeysWithValues: layers.map { ($0.key.uuidString, $0.value) }), forKey: .layers)
        try container.encode(systemFields, forKey: .systemFields)
        try container.encode(uploadedFiles.sorted(), forKey: .uploadedFiles)
        try container.encode(mediaOwners, forKey: .mediaOwners)
        try container.encode(unsupportedRecordNames.sorted(), forKey: .unsupportedRecordNames)
        // Desligado não vai ao disco: o estado comum continua com os mesmos bytes de antes do campo.
        if needsFullFetch { try container.encode(true, forKey: .needsFullFetch) }
        if isAwaitingFirstFetch { try container.encode(true, forKey: .isAwaitingFirstFetch) }
        if isAdopted { try container.encode(true, forKey: .isAdopted) }
    }
}

public enum SyncMetadataStoreError: Error, Equatable, Sendable {
    /// O arquivo existe mas não pôde ser lido. Nada é apagado nem trocado: quem chama decide se refaz o estado a partir do iCloud.
    case corrupted(String)
}

/// O que este Mac sabe do iCloud, guardado em disco fora dos pacotes dos murais (em `Application Support/Mural/Sync/`, como as
/// prévias de link e as capas): quem chama passa a pasta.
///
/// Um arquivo por mural em `boards/<UUID>.json` e, por banco, um em `engine-private.data` e `engine-shared.data`, com o estado opaco
/// do motor de sincronização, e outro em `declined-private.json` e `declined-shared.json`, com as zonas recusadas. Toda gravação é
/// atômica: uma queda no meio deixa o arquivo antigo, nunca metade de um novo.
public actor SyncMetadataStore {
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    // MARK: Estado de cada mural

    /// O estado do mural, ou `nil` se este Mac ainda não sabe nada dele.
    /// - Throws: `SyncMetadataStoreError.corrupted` se o arquivo existe e não pode ser lido.
    public func state(for id: BoardID) throws -> BoardSyncState? {
        let url = stateURL(for: id)
        guard let data = try readIfPresent(url) else { return nil }
        do {
            return try SyncJSON.decode(BoardSyncState.self, from: data)
        } catch {
            throw SyncMetadataStoreError.corrupted("\(url.lastPathComponent): \(error)")
        }
    }

    public func save(_ state: BoardSyncState, for id: BoardID) throws {
        try FileManager.default.createDirectory(at: boardsDirectory, withIntermediateDirectories: true)
        try SyncJSON.encode(state).write(to: stateURL(for: id), options: .atomic)
    }

    /// Esquece o mural. Não é erro não haver nada a esquecer.
    public func remove(_ id: BoardID) throws {
        do {
            try FileManager.default.removeItem(at: stateURL(for: id))
        } catch let error as CocoaError where Self.isMissingFile(error) {
            return
        }
    }

    /// Os murais de que há estado, em ordem fixa. Nomes que não são `<UUID>.json` (sobras, arquivos do sistema) ficam de fora.
    public func boardIDs() throws -> [BoardID] {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: boardsDirectory, includingPropertiesForKeys: [.isRegularFileKey])
        } catch let error as CocoaError where Self.isMissingFile(error) {
            return []
        }
        let ids = urls.compactMap { url -> UUID? in
            guard url.pathExtension == "json", (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else {
                return nil
            }
            // Só o nome que `stateURL(for:)` produz: outro formato do mesmo UUID não seria achado por `state(for:)`.
            let name = url.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: name), id.uuidString == name else { return nil }
            return id
        }
        return ids.sorted { $0.uuidString < $1.uuidString }.map { BoardID(rawValue: $0) }
    }

    // MARK: Estado do motor

    /// O estado do motor de sincronização do banco, ou `nil` se ainda não foi gravado.
    public func engineState(for scope: CloudDatabaseScope) throws -> Data? {
        try readIfPresent(engineURL(for: scope))
    }

    public func saveEngineState(_ data: Data, for scope: CloudDatabaseScope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: engineURL(for: scope), options: .atomic)
    }

    // MARK: Zonas recusadas

    /// As zonas do banco que este Mac excluiu, abandonou ou tirou do iCloud: o coordenador não as adota de novo até o servidor
    /// confirmar o apagamento. Vazio se nenhuma foi recusada.
    /// - Throws: `SyncMetadataStoreError.corrupted` se o arquivo existe e não pode ser lido.
    public func declinedZones(for scope: CloudDatabaseScope) throws -> Set<CloudZoneID> {
        let url = declinedURL(for: scope)
        guard let data = try readIfPresent(url) else { return [] }
        do {
            return Set(try SyncJSON.decode([CloudZoneID].self, from: data))
        } catch {
            throw SyncMetadataStoreError.corrupted("\(url.lastPathComponent): \(error)")
        }
    }

    /// Troca a lista de zonas recusadas do banco. Vai em lista ordenada, para o mesmo conjunto dar sempre os mesmos bytes.
    public func saveDeclinedZones(_ zones: Set<CloudZoneID>, for scope: CloudDatabaseScope) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ordered = zones.sorted { ($0.ownerName, $0.name) < ($1.ownerName, $1.name) }
        try SyncJSON.encode(ordered).write(to: declinedURL(for: scope), options: .atomic)
    }

    // MARK: Interno

    private var boardsDirectory: URL {
        directory.appendingPathComponent("boards", isDirectory: true)
    }

    private func stateURL(for id: BoardID) -> URL {
        boardsDirectory.appendingPathComponent("\(id.rawValue.uuidString).json", isDirectory: false)
    }

    private func engineURL(for scope: CloudDatabaseScope) -> URL {
        directory.appendingPathComponent("engine-\(scope.rawValue).data", isDirectory: false)
    }

    private func declinedURL(for scope: CloudDatabaseScope) -> URL {
        directory.appendingPathComponent("declined-\(scope.rawValue).json", isDirectory: false)
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where Self.isMissingFile(error) {
            return nil
        }
    }

    private static func isMissingFile(_ error: CocoaError) -> Bool {
        error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile
    }
}
