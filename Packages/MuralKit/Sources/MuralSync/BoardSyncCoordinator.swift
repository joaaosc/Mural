import Foundation
import MuralKit

// O modelo de eventos imita o do `CKSyncEngine`: o motor diz ao coordenador o que foi enviado (`handleSent`), o que falhou
// (`SyncSaveFailure`) e o que chegou (`handleFetched`, `handleZoneDeleted`), e o coordenador responde com o que continua pendente
// e monta os registros que o motor pede (`record(for:)`). O motor de verdade só traduz os eventos do CloudKit para estas chamadas;
// o `InMemorySyncEngine` faz o mesmo com o iCloud falso. Assim toda a decisão fica aqui, testável sem CloudKit.

/// O lado do app: o mural como está e onde juntar o que chegou.
public protocol BoardSyncHost: Sendable {
    /// O mural como está agora, ou `nil` se o app não o tem.
    func localBoard(_ id: BoardID) async -> LocalBoardSnapshot?

    /// Junta o que chegou (`BoardMerge.apply(changes, to: local, base:)` e o nome por `ReceivedChanges.mergedName(local:)`), grava e
    /// põe os arquivos em `Items/`. Não chama
    /// `pendingChanges(for:)`: quem calcula as pendências depois de uma junção é o coordenador, com o estado novo já gravado
    /// (senão o que acabou de chegar pareceria mudança deste Mac e voltaria ao iCloud). O coordenador espera esta chamada terminar
    /// antes de tratar o próximo evento, então ela também não chama `handleSent`, `handleFetched`, `handleZoneDeleted`,
    /// `startTracking` nem `stopTracking`.
    ///
    /// Só volta depois de o mural junto estar gravado em disco. Se a gravação falhar, lança: o coordenador mantém o estado antigo (o
    /// que combina com o disco) e marca o mural para uma busca completa. Voltar sem gravar deixaria o disco antigo com a base nova, e
    /// os cartões que chegaram pareceriam apagados aqui, com o apagamento subindo para todos.
    func applyRemote(_ id: BoardID, received: ReceivedChanges) async throws

    /// O mural deixou de existir no iCloud para este Mac.
    func boardRemoved(_ id: BoardID, reason: BoardRemovalReason) async

    /// Cria o pacote local de um mural que já existe no iCloud e este Mac ainda não tem (`BoardSyncCoordinator.adoptZone`): o que
    /// outra pessoa compartilhou, ou o do próprio dono vindo de outro Mac dele. O pacote nasce vazio e provisório, com este `id` e
    /// `cloud` já gravado: o conteúdo e o nome verdadeiros chegam na primeira busca completa, por `applyRemote`.
    /// - Parameter name: o nome provisório; `nil` deixa o host escolher um.
    /// - Returns: `false` se já existe pacote com o `id`, sem tocar nele.
    func adoptBoard(_ id: BoardID, cloud: BoardCloudInfo, name: String?) async throws -> Bool
}

public enum BoardSyncAdoptionError: Error, Equatable, Sendable {
    /// O host não cria pacotes de murais que vieram do iCloud.
    case unsupported
}

extension BoardSyncHost {
    /// Para quem ainda não adota zonas novas: a adoção falha com `BoardSyncAdoptionError.unsupported`, e a zona fica sem acompanhar.
    public func adoptBoard(_ id: BoardID, cloud: BoardCloudInfo, name: String?) async throws -> Bool {
        throw BoardSyncAdoptionError.unsupported
    }
}

/// O mural como o app o tem agora.
public struct LocalBoardSnapshot: Sendable {
    public var name: String
    public var board: Board
    /// A pasta `Items/` do mural, onde ficam os arquivos de mídia.
    public var itemsDirectory: URL

    public init(name: String, board: Board, itemsDirectory: URL) {
        self.name = name
        self.board = board
        self.itemsDirectory = itemsDirectory
    }
}

/// Por que o mural deixou de existir no iCloud para este Mac.
public enum BoardRemovalReason: Equatable, Sendable {
    /// A zona foi apagada: o dono apagou o mural ou parou de compartilhá-lo.
    case zoneDeleted
    /// Esta pessoa perdeu o acesso ao mural que recebeu por convite.
    case accessRevoked
    /// A conta do iCloud deste Mac mudou: o que havia pertence a outra conta.
    case accountChanged
    /// A pessoa apagou os dados do app no iCloud (Ajustes, gerenciar armazenamento) ou redefiniu os dados criptografados: só a cópia
    /// na nuvem sumiu. O mural continua sendo dela, então quem recebe o aviso não apaga o pacote local; só volta o mural a ser só
    /// local, sem sincronização.
    case cloudDataErased
}

/// Por que o iCloud recusou gravar um registro. O motor traduz o erro do CloudKit para um destes casos.
public enum SyncSaveFailure: Equatable, Sendable {
    /// O registro mudou no iCloud desde a última vez; traz a versão do servidor.
    case conflict(serverRecord: CloudRecord)
    /// Apagado no iCloud enquanto este Mac o regravava. Vale só para gravação: apagar o que já não existe conta como apagado.
    case unknownItem(CloudRecordID)
    case zoneMissing(CloudZoneID)
    /// Sem espaço no iCloud do dono do mural.
    case quotaExceeded(CloudRecordID)
    /// Quem só pode ver o mural tentou gravar.
    case permission(CloudRecordID)
    case other(CloudRecordID, String)
}

/// O que impede um mural de sincronizar por inteiro, para o app avisar a pessoa. Existe só em memória: se o problema persiste, a
/// próxima tentativa o traz de volta.
public enum SyncIssue: Equatable, Sendable {
    /// Sem espaço no iCloud do dono do mural.
    case quotaExceeded
    /// Esta pessoa só pode ver o mural, e o iCloud recusou mudanças dela.
    case readOnly
    /// O cartão passa do limite de um registro do iCloud e fica de fora até o conteúdo dele mudar.
    case recordTooLarge(UUID)
    /// O mural foi gravado por um app mais novo: nada é enviado até este app ser atualizado.
    case needsNewerApp
    /// O que chegou do iCloud não pôde ser gravado neste Mac; o mural será buscado de novo inteiro.
    case localSaveFailed
    /// O mural acabou de ser adotado do iCloud e baixa pela primeira vez. É informativo, não um problema: some sozinho quando a
    /// busca completa termina, e até lá nada é enviado.
    case awaitingFirstFetch
    case other(String)
}

public enum BoardSyncCoordinatorError: Error, Equatable, Sendable {
    /// O banco do mural (`BoardCloudInfo.database`) não é o do coordenador.
    case wrongDatabase(BoardID)
}

/// A orquestração da sincronização dos murais de um banco do iCloud: junta o estado guardado (`SyncMetadataStore`), a regra
/// (`SyncCore`) e o app (`BoardSyncHost`) sem depender do CloudKit.
///
/// O estado de cada mural é lido e gravado a cada evento, porque o app pode fechar a qualquer momento. Zona que não é de um mural
/// acompanhado neste banco é ignorada.
///
/// **Ordem ao receber** (`handleFetched` e os conflitos de `handleSent`): o estado novo é calculado numa cópia
/// (`SyncCore.receive`), `host.applyRemote` junta o que chegou e só depois que ele volta o estado novo é gravado e passa a valer.
/// Enquanto o host junta, `pendingChanges(for:)` e `record(for:)` daquele mural seguem no estado anterior, e o actor aceita essas
/// chamadas durante a espera. Com a base nova e o mural local ainda antigo, um cartão que acabou de chegar pareceria apagado aqui e
/// iria como `.delete` ao iCloud. Se o app cair entre juntar e gravar, o pior caso é reenviar valores iguais aos do iCloud, que o
/// conflito resolve.
///
/// **Zonas novas**: a zona de um mural que este Mac ainda não tem (outra pessoa o compartilhou, ou o dono o criou em outro Mac dele)
/// entra por `adoptZone(_:cloud:name:)`. O host cria o pacote local provisório e o estado nasce `isAwaitingFirstFetch`: nada é
/// enviado até a busca completa trazer o conteúdo e o nome verdadeiros. O que este Mac excluiu, abandonou ou tirou do iCloud fica em
/// `declinedZones()` e não é adotado de novo até o servidor confirmar o apagamento (`handleZoneDeleted`).
///
/// **Um evento de cada vez**: como a espera pelo host abre espaço para outro evento ler o mesmo estado antigo e gravar por cima do
/// primeiro, os que mudam o estado (`startTracking`, `stopTracking`, `adoptZone`, `declineZone`, `handleSent`, `handleFetched`,
/// `handleZoneDeleted`) rodam um por vez, na ordem de chegada. `pendingChanges(for:)` e `record(for:)` só leem e não esperam.
public actor BoardSyncCoordinator {
    /// O resultado de `adoptZone(_:cloud:name:)`.
    public enum AdoptionResult: Equatable, Sendable {
        /// O host criou o pacote local e o mural passou a ser acompanhado, esperando a primeira busca completa.
        case adopted
        /// Este banco já acompanha o mural nessa zona: nada mudou.
        case alreadyTracked
        /// Este Mac recusou a zona e o servidor ainda não confirmou o apagamento dela.
        case declined
        /// Já existe um mural com o mesmo id neste Mac (acompanhado em outro banco, ou um pacote local): nada foi tocado.
        case conflict
        /// O nome da zona não é o de uma zona de mural.
        case notABoardZone
    }

    private let scope: CloudDatabaseScope
    private let store: SyncMetadataStore
    private let host: any BoardSyncHost

    // O que segue só existe em memória.
    /// Os murais cuja versão do formato no iCloud passa da que esta build lê.
    private var newerAppBoards = Set<BoardID>()
    /// Os murais marcados para busca completa (`BoardSyncState.needsFullFetch`), para `issues()`.
    private var fullFetchBoards = Set<BoardID>()
    /// Os murais que esperam a primeira busca (`BoardSyncState.isAwaitingFirstFetch`), para `issues()`.
    private var awaitingFirstFetchBoards = Set<BoardID>()
    /// A recusa do iCloud na última tentativa de envio de cada mural; some quando um envio dele passa sem recusa.
    private var sendIssues: [BoardID: SyncIssue] = [:]
    /// Os cartões cujo registro estourou o limite, com o valor (forma compartilhada) que estourou.
    private var oversizedCards: [BoardID: [UUID: BoardItem]] = [:]
    /// Os registros ilegíveis ignorados de cada mural, até chegarem legíveis ou serem apagados.
    private var unreadableRecords: [BoardID: Set<String>] = [:]

    private var isHandlingEvent = false
    private var queuedEvents: [CheckedContinuation<Void, Never>] = []

    public init(scope: CloudDatabaseScope, store: SyncMetadataStore, host: any BoardSyncHost) {
        self.scope = scope
        self.store = store
        self.host = host
    }

    // MARK: Murais acompanhados

    /// Os murais de que há estado guardado neste banco, em ordem fixa.
    /// - Throws: `SyncMetadataStoreError.corrupted` se algum estado não pode ser lido: quem chama decide se o refaz.
    public func boardIDs() async throws -> [BoardID] {
        var ids: [BoardID] = []
        for id in try await store.boardIDs() {
            if try await loadState(for: id) != nil { ids.append(id) }
        }
        return ids
    }

    /// Passa a acompanhar o mural na zona dada, com a base vazia: nada se sabe do iCloud, então tudo o que há aqui é pendente.
    /// Se o mural já é acompanhado na mesma zona, o estado guardado fica (perdê-lo reenviaria tudo) e só as informações da nuvem,
    /// como a permissão, são atualizadas. É também por aqui que chega a permissão nova depois de uma recusa por permissão, então a
    /// recusa anterior é esquecida e o envio volta a ser tentado se a permissão deixar.
    /// - Throws: `BoardSyncCoordinatorError.wrongDatabase` se `cloud.database` não é o banco deste coordenador.
    public func startTracking(_ id: BoardID, cloud: BoardCloudInfo) async throws -> Set<PendingChange> {
        guard cloud.database.rawValue == scope.rawValue else { throw BoardSyncCoordinatorError.wrongDatabase(id) }
        await acquireEventLock()
        defer { releaseEventLock() }

        var state = BoardSyncState(cloud: cloud)
        if var existing = try await loadState(for: id), existing.cloud.zoneName == cloud.zoneName,
            existing.cloud.zoneOwnerName == cloud.zoneOwnerName
        {
            existing.cloud = cloud
            state = existing
        }
        try await commit(state, for: id)
        sendIssues[id] = nil
        return await pendingChanges(for: id, state: state)
    }

    /// Esquece o mural: apaga o estado guardado. Não chama o host, que é quem pediu.
    public func stopTracking(_ id: BoardID) async throws {
        await acquireEventLock()
        defer { releaseEventLock() }
        guard try await loadState(for: id) != nil else { return }
        try await store.remove(id)
        forgetInMemory(id)
    }

    /// Este banco acompanha o mural: há estado guardado dele aqui.
    public func isTracking(_ id: BoardID) async throws -> Bool {
        try await loadState(for: id) != nil
    }

    // MARK: Zonas novas

    /// Adota a zona de um mural que este Mac ainda não tem: a que outra pessoa compartilhou, ou a do próprio dono vinda de outro Mac
    /// dele. O host cria o pacote local (`BoardSyncHost.adoptBoard`) e o estado nasce com `isAwaitingFirstFetch`: o pacote é
    /// provisório e vazio, então nada é enviado até a busca completa (`zonesNeedingFullFetch()`) trazer o conteúdo e o nome
    /// verdadeiros.
    ///
    /// Confere nesta ordem: o nome da zona (`.notABoardZone`), as zonas recusadas deste banco, pelo nome (`.declined`), o estado
    /// guardado deste banco na mesma zona (`.alreadyTracked`) e o estado do mesmo id em qualquer banco, ou um pacote local com esse
    /// id (`.conflict`).
    /// - Parameters:
    ///   - zone: a zona como este Mac a vê; o id do mural vem do nome dela.
    ///   - cloud: onde o mural vive e o que esta pessoa pode fazer nele; descreve a mesma zona. No banco compartilhado a permissão só
    ///     chega com o convite, então quem adota pode começar com `.readOnly` e corrigi-la depois por `startTracking`.
    ///   - name: o nome provisório do pacote; `nil` deixa o host escolher.
    /// - Throws: `BoardSyncCoordinatorError.wrongDatabase` se `cloud.database` não é o banco deste coordenador;
    ///   `BoardSyncAdoptionError.unsupported` se o host não cria pacotes de murais do iCloud.
    public func adoptZone(_ zone: CloudZoneID, cloud: BoardCloudInfo, name: String?) async throws -> AdoptionResult {
        guard let id = CloudSchema.boardID(fromZoneName: zone.name) else { return .notABoardZone }
        guard cloud.database.rawValue == scope.rawValue else { throw BoardSyncCoordinatorError.wrongDatabase(id) }
        await acquireEventLock()
        defer { releaseEventLock() }

        if try await store.declinedZones(for: scope).contains(where: { $0.name == zone.name }) { return .declined }
        // Sem o filtro de banco: o mesmo id acompanhado no outro banco também é conflito.
        if let existing = try await store.state(for: id) {
            let isHere = existing.cloud.database.rawValue == scope.rawValue
            let isSameZone = existing.cloud.zoneName == zone.name && existing.cloud.zoneOwnerName == zone.ownerName
            return isHere && isSameZone ? .alreadyTracked : .conflict
        }
        guard try await host.adoptBoard(id, cloud: cloud, name: name) else { return .conflict }
        try await commit(BoardSyncState(cloud: cloud, isAwaitingFirstFetch: true), for: id)
        return .adopted
    }

    /// Guarda a zona do mural na lista de recusadas: este Mac excluiu, abandonou ou tirou o mural do iCloud, e a zona, que ainda
    /// existe no servidor, não pode ser adotada de novo (`adoptZone` devolve `.declined`) até o servidor confirmar o apagamento
    /// (`handleZoneDeleted`). Quem chama para de acompanhar o mural depois (`stopTracking`). Sem estado guardado do mural neste
    /// banco não há zona a guardar, e nada acontece.
    public func declineZone(of id: BoardID) async throws {
        await acquireEventLock()
        defer { releaseEventLock() }
        guard let state = try await loadState(for: id) else { return }
        var declined = try await store.declinedZones(for: scope)
        declined.insert(CloudZoneID(name: state.cloud.zoneName, ownerName: state.cloud.zoneOwnerName))
        try await store.saveDeclinedZones(declined, for: scope)
    }

    /// As zonas recusadas deste banco: não são adotadas até o servidor confirmar o apagamento.
    public func declinedZones() async throws -> Set<CloudZoneID> {
        try await store.declinedZones(for: scope)
    }

    // MARK: O que enviar

    /// O que falta enviar do mural: a diferença entre o mural do app e a base (`SyncCore.pendingChanges`).
    ///
    /// Vazio se o mural não é acompanhado, se foi gravado por um app mais novo (`SyncIssue.needsNewerApp`) ou se esta pessoa só
    /// pode ver o mural (veja `canSend`): nada é enviado. Um cartão cujo registro estourou o limite fica de fora enquanto o
    /// conteúdo dele não mudar.
    public func pendingChanges(for id: BoardID) async throws -> Set<PendingChange> {
        guard let state = try await loadState(for: id) else { return [] }
        return await pendingChanges(for: id, state: state)
    }

    /// O registro a enviar para `id` (`SyncCore.record`), ou `nil` se o mural não é acompanhado, nada dele pode ser enviado
    /// (`canSend`) ou o que o registro representa já não existe aqui.
    /// - Throws: `CardRecordMappingError.recordTooLarge` se o cartão passa do limite do iCloud. O cartão sai das pendências até o
    ///   conteúdo mudar e o mural ganha `SyncIssue.recordTooLarge`.
    public func record(for id: CloudRecordID) async throws -> CloudRecord? {
        guard let boardID = CloudSchema.boardID(fromZoneName: id.zone.name), let state = try await loadState(for: boardID),
            canSend(state, for: boardID), let snapshot = await host.localBoard(boardID)
        else { return nil }
        do {
            return try SyncCore.record(
                for: id, state: state, local: snapshot.board, name: snapshot.name, itemsDirectory: snapshot.itemsDirectory)
        } catch CardRecordMappingError.recordTooLarge(let itemID) {
            if let item = snapshot.board.item(id: itemID) {
                oversizedCards[boardID, default: [:]][itemID] = SharedFieldPolicy.shared(item)
            }
            throw CardRecordMappingError.recordTooLarge(itemID)
        }
    }

    // MARK: Eventos do motor

    /// O iCloud respondeu a um envio. `saved` e `deleted` foram aceitos (os registros com os campos de sistema que o servidor deu) e
    /// `failures` foram recusados; o resto do lote, que o iCloud trata registro a registro, pode ter passado em parte.
    ///
    /// Os aceitos entram na base (`SyncCore.confirmSaved`/`confirmDeleted`) e o estado é gravado. Um conflito traz a versão do
    /// servidor e um `unknownItem` o registro apagado: os dois passam por `SyncCore.receive` e `host.applyRemote`, como o que chega
    /// de uma busca. `zoneMissing` remove o mural como `handleZoneDeleted(_:reason:)` com `.zoneDeleted`. Cota e permissão viram
    /// `issues()`.
    /// - Returns: o que continua pendente dos murais do lote, para o motor devolver ao `CKSyncEngine`.
    public func handleSent(
        saved: [CloudRecord], deleted: [CloudRecordID], failures: [SyncSaveFailure]
    ) async throws -> Set<PendingChange> {
        await acquireEventLock()
        defer { releaseEventLock() }

        var pending = Set<PendingChange>()
        for (id, batch) in Self.batches(saved: saved, deleted: deleted, failures: failures) {
            guard var state = try await loadState(for: id) else { continue }
            if batch.failures.contains(where: { if case .zoneMissing = $0 { true } else { false } }) {
                try await remove(id, reason: .zoneDeleted)
                continue
            }

            // O que o iCloud aceitou vale mesmo que o resto do lote tenha falhado, e fica gravado antes de esperar o host.
            if !batch.saved.isEmpty || !batch.deleted.isEmpty {
                try SyncCore.confirmSaved(batch.saved, into: &state)
                SyncCore.confirmDeleted(batch.deleted, into: &state)
                try await commit(state, for: id)
            }

            var serverRecords: [CloudRecord] = []
            var vanished: [CloudRecordID] = []
            for failure in batch.failures {
                switch failure {
                case .conflict(let serverRecord): serverRecords.append(serverRecord)
                case .unknownItem(let recordID): vanished.append(recordID)
                case .quotaExceeded, .permission, .other, .zoneMissing: break
                }
            }
            if !serverRecords.isEmpty || !vanished.isEmpty {
                try await receive(serverRecords, deleted: vanished, into: &state, for: id)
            }

            noteSendOutcome(of: batch, for: id)
            pending.formUnion(await pendingChanges(for: id, state: state))
        }
        return pending
    }

    /// Chegou o que outras pessoas gravaram ou apagaram. Para cada mural: junta ao estado e ao mural do app (na ordem descrita no
    /// tipo) e grava o estado novo.
    /// - Returns: as pendências desses murais com o estado novo, para o motor entregar ao `CKSyncEngine`.
    public func handleFetched(saved: [CloudRecord], deleted: [CloudRecordID]) async throws -> Set<PendingChange> {
        await acquireEventLock()
        defer { releaseEventLock() }

        var pending = Set<PendingChange>()
        for (id, batch) in Self.batches(saved: saved, deleted: deleted, failures: []) {
            guard var state = try await loadState(for: id) else { continue }
            try await receive(batch.saved, deleted: batch.deleted, into: &state, for: id)
            pending.formUnion(await pendingChanges(for: id, state: state))
        }
        return pending
    }

    /// As zonas dos murais que precisam de busca completa, como este Mac as vê: os marcados porque o host não conseguiu gravar o que
    /// chegou e os adotados que esperam a primeira busca (`BoardSyncState.isAwaitingFirstFetch`). O motor busca cada uma inteira e
    /// entrega a `handleFullFetch(_:records:)`.
    public func zonesNeedingFullFetch() async throws -> [CloudZoneID] {
        var zones: [CloudZoneID] = []
        for id in try await store.boardIDs() {
            guard let state = try await loadState(for: id), state.needsFullFetch || state.isAwaitingFirstFetch else { continue }
            zones.append(CloudZoneID(name: state.cloud.zoneName, ownerName: state.cloud.zoneOwnerName))
        }
        return zones
    }

    /// A zona inteira, buscada de novo: todos os registros que ela tem agora. O que este Mac conhecia e não veio foi apagado no
    /// iCloud enquanto ele não conseguia gravar, então entra como apagado. Depois de juntar e gravar, as marcas de busca completa e
    /// de espera pela primeira busca saem.
    /// - Returns: as pendências do mural com o estado novo, para o motor.
    public func handleFullFetch(_ zone: CloudZoneID, records: [CloudRecord]) async throws -> Set<PendingChange> {
        guard let id = CloudSchema.boardID(fromZoneName: zone.name) else { return [] }
        await acquireEventLock()
        defer { releaseEventLock() }
        guard var state = try await loadState(for: id) else { return [] }

        let inZone = records.filter { $0.id.zone.name == zone.name }
        let present = Set(inZone.map(\.id.name))
        let missing = Self.knownRecordNames(in: state).subtracting(present).sorted().map { CloudRecordID(zone: zone, name: $0) }
        try await receive(inZone, deleted: missing, into: &state, for: id, completesFullFetch: true)
        return await pendingChanges(for: id, state: state)
    }

    /// A zona do mural deixou de existir para este Mac: apaga o estado guardado e avisa o host. O servidor confirmou o apagamento,
    /// então a zona também sai da lista de recusadas (`declinedZones()`), mesmo sem estado guardado do mural: a recusa só vale
    /// enquanto a zona ainda existe lá. A lista fica por último, para um arquivo dela ilegível não impedir a saída do mural.
    public func handleZoneDeleted(_ zone: CloudZoneID, reason: BoardRemovalReason) async throws {
        guard let id = CloudSchema.boardID(fromZoneName: zone.name) else { return }
        await acquireEventLock()
        defer { releaseEventLock() }
        if try await loadState(for: id) != nil { try await remove(id, reason: reason) }
        let declined = try await store.declinedZones(for: scope)
        let remaining = declined.filter { $0.name != zone.name }
        if remaining.count != declined.count { try await store.saveDeclinedZones(remaining, for: scope) }
    }

    /// O que está impedindo cada mural de sincronizar, um por mural. Havendo vários, vale o mais grave: app mais novo, a gravação
    /// que falhou neste Mac, a espera pela primeira busca (`SyncIssue.awaitingFirstFetch`, só informativa), a recusa do iCloud, o
    /// cartão grande demais e, por último, os registros ilegíveis.
    public func issues() -> [BoardID: SyncIssue] {
        var boards = newerAppBoards
        boards.formUnion(fullFetchBoards)
        boards.formUnion(awaitingFirstFetchBoards)
        boards.formUnion(sendIssues.keys)
        boards.formUnion(oversizedCards.keys)
        boards.formUnion(unreadableRecords.keys)
        var result: [BoardID: SyncIssue] = [:]
        for id in boards { result[id] = issue(for: id) }
        return result
    }

    // MARK: Interno

    /// Um evento por vez: quem chega com outro em andamento espera a vez. A trava passa direto para o próximo da fila.
    private func acquireEventLock() async {
        guard isHandlingEvent else {
            isHandlingEvent = true
            return
        }
        await withCheckedContinuation { queuedEvents.append($0) }
    }

    private func releaseEventLock() {
        if queuedEvents.isEmpty {
            isHandlingEvent = false
        } else {
            queuedEvents.removeFirst().resume()
        }
    }

    /// O estado do mural, ou `nil` se não é acompanhado neste banco.
    private func loadState(for id: BoardID) async throws -> BoardSyncState? {
        guard let state = try await store.state(for: id), state.cloud.database.rawValue == scope.rawValue else { return nil }
        noteFormatVersion(of: state, for: id)
        return state
    }

    private func commit(_ state: BoardSyncState, for id: BoardID) async throws {
        try await store.save(state, for: id)
        noteFormatVersion(of: state, for: id)
    }

    /// Incorpora o que chegou, na ordem descrita no tipo: estado novo numa cópia, o host junta e só então o estado é gravado.
    ///
    /// Se o host não consegue gravar, o estado antigo fica (é ele que combina com o disco) e o mural é marcado para busca completa:
    /// o motor já passou dessas mudanças e não as traria de novo. O erro não sobe, para os outros murais do evento seguirem.
    private func receive(
        _ saved: [CloudRecord], deleted: [CloudRecordID], into state: inout BoardSyncState, for id: BoardID,
        completesFullFetch: Bool = false
    ) async throws {
        var updated = state
        let received = try SyncCore.receive(saved: saved, deleted: deleted, into: &updated)
        if !received.isEmpty {
            do {
                try await host.applyRemote(id, received: received)
            } catch {
                state.needsFullFetch = true
                try await commit(state, for: id)
                return
            }
        }
        if completesFullFetch {
            updated.needsFullFetch = false
            updated.isAwaitingFirstFetch = false
        }
        try await commit(updated, for: id)
        state = updated
        noteUnreadable(received.skippedRecordNames, arrived: saved, deleted: deleted, for: id)
    }

    /// Todos os registros de que o estado sabe: cartões e textos livres da base, o mural, os arquivos enviados, os de app mais novo e
    /// os que têm campos de sistema guardados.
    private static func knownRecordNames(in state: BoardSyncState) -> Set<String> {
        var names = Set(state.systemFields.keys)
        names.formUnion(state.base.items.map(\.id.uuidString))
        names.formUnion(state.base.freeTexts.map(\.id.uuidString))
        names.formUnion(state.uploadedFiles)
        names.formUnion(state.unsupportedRecordNames)
        if state.baseName != nil { names.insert(CloudSchema.muralRecordName) }
        return names
    }

    private func remove(_ id: BoardID, reason: BoardRemovalReason) async throws {
        try await store.remove(id)
        forgetInMemory(id)
        await host.boardRemoved(id, reason: reason)
    }

    private func pendingChanges(for id: BoardID, state: BoardSyncState) async -> Set<PendingChange> {
        // O estado vem antes do mural do app: se um evento terminar entre as duas leituras, o par é (estado antigo, mural novo), que
        // só reenvia valores iguais, e nunca (estado novo, mural antigo), que apagaria o que acabou de chegar.
        guard canSend(state, for: id), let snapshot = await host.localBoard(id) else { return [] }
        var pending = SyncCore.pendingChanges(
            state: state, local: snapshot.board, name: snapshot.name, itemsDirectory: snapshot.itemsDirectory)
        guard var oversized = oversizedCards[id] else { return pending }

        let current = Dictionary(
            snapshot.board.items.map { ($0.id, SharedFieldPolicy.shared($0)) }, uniquingKeysWith: { first, _ in first })
        for (itemID, value) in oversized {
            if current[itemID] == value {
                pending = pending.filter { $0.recordID.name != itemID.uuidString }
            } else {
                oversized[itemID] = nil
            }
        }
        oversizedCards[id] = oversized.isEmpty ? nil : oversized
        return pending
    }

    /// Se algo do mural pode ir ao iCloud. Não pode o mural gravado por um app mais novo (a versão do formato dele cairia) nem o de
    /// quem só pode ver: pela permissão guardada, ou porque o iCloud recusou por permissão um envio (a permissão mudou e o app ainda
    /// não sabe). Sem isso o motor reenviaria a mesma recusa sem fim; a permissão nova chega por `startTracking`, que esquece a recusa.
    private func canSend(_ state: BoardSyncState, for id: BoardID) -> Bool {
        !requiresNewerApp(state) && !state.cloud.isReadOnly && sendIssues[id] != .readOnly
    }

    /// O mural gravado por um app mais novo não é regravado: a versão do formato dele cairia.
    private func requiresNewerApp(_ state: BoardSyncState) -> Bool {
        (state.baseBoardFormatVersion ?? 0) > Board.currentFormatVersion
    }

    private func noteFormatVersion(of state: BoardSyncState, for id: BoardID) {
        if requiresNewerApp(state) {
            newerAppBoards.insert(id)
        } else {
            newerAppBoards.remove(id)
        }
        if state.needsFullFetch {
            fullFetchBoards.insert(id)
        } else {
            fullFetchBoards.remove(id)
        }
        if state.isAwaitingFirstFetch {
            awaitingFirstFetchBoards.insert(id)
        } else {
            awaitingFirstFetchBoards.remove(id)
        }
    }

    /// Anota o resultado de um envio: a recusa vira aviso, e um lote em que o iCloud aceitou algo sem recusar nada limpa o aviso.
    private func noteSendOutcome(of batch: Batch, for id: BoardID) {
        var refusals: [SyncIssue] = []
        for failure in batch.failures {
            switch failure {
            case .permission: refusals.append(.readOnly)
            case .quotaExceeded: refusals.append(.quotaExceeded)
            case .other(_, let message): refusals.append(.other(message))
            case .conflict, .unknownItem, .zoneMissing: break
            }
        }
        if let issue = refusals.first(where: { $0 == .readOnly }) ?? refusals.first(where: { $0 == .quotaExceeded }) ?? refusals.first {
            sendIssues[id] = issue
        } else if !batch.saved.isEmpty || !batch.deleted.isEmpty {
            sendIssues[id] = nil
        }
    }

    /// Guarda os registros ilegíveis da leva e tira da lista os que chegaram legíveis ou foram apagados.
    private func noteUnreadable(_ names: [String], arrived: [CloudRecord], deleted: [CloudRecordID], for id: BoardID) {
        var unreadable = unreadableRecords[id] ?? []
        for record in arrived { unreadable.remove(record.id.name) }
        for recordID in deleted { unreadable.remove(recordID.name) }
        unreadable.formUnion(names)
        unreadableRecords[id] = unreadable.isEmpty ? nil : unreadable
    }

    private func forgetInMemory(_ id: BoardID) {
        newerAppBoards.remove(id)
        fullFetchBoards.remove(id)
        awaitingFirstFetchBoards.remove(id)
        sendIssues[id] = nil
        oversizedCards[id] = nil
        unreadableRecords[id] = nil
    }

    private func issue(for id: BoardID) -> SyncIssue? {
        if newerAppBoards.contains(id) { return .needsNewerApp }
        if fullFetchBoards.contains(id) { return .localSaveFailed }
        if awaitingFirstFetchBoards.contains(id) { return .awaitingFirstFetch }
        if let issue = sendIssues[id] { return issue }
        if let itemID = oversizedCards[id]?.keys.min(by: { $0.uuidString < $1.uuidString }) { return .recordTooLarge(itemID) }
        if let names = unreadableRecords[id], !names.isEmpty {
            return .other("registros ilegíveis ignorados: " + names.sorted().joined(separator: ", "))
        }
        return nil
    }

    /// Os registros e as falhas de um evento que são de um mural.
    private struct Batch {
        var saved: [CloudRecord] = []
        var deleted: [CloudRecordID] = []
        var failures: [SyncSaveFailure] = []
    }

    /// Separa por mural, em ordem fixa. Zona que não tem nome de zona de mural fica de fora.
    private static func batches(
        saved: [CloudRecord], deleted: [CloudRecordID], failures: [SyncSaveFailure]
    ) -> [(id: BoardID, batch: Batch)] {
        var byBoard: [BoardID: Batch] = [:]
        for record in saved {
            if let id = CloudSchema.boardID(fromZoneName: record.id.zone.name) { byBoard[id, default: Batch()].saved.append(record) }
        }
        for recordID in deleted {
            if let id = CloudSchema.boardID(fromZoneName: recordID.zone.name) { byBoard[id, default: Batch()].deleted.append(recordID) }
        }
        for failure in failures {
            if let id = CloudSchema.boardID(fromZoneName: failure.zone.name) { byBoard[id, default: Batch()].failures.append(failure) }
        }
        return byBoard.keys.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }.map { ($0, byBoard[$0] ?? Batch()) }
    }
}

extension SyncSaveFailure {
    /// A zona do registro que falhou.
    var zone: CloudZoneID {
        switch self {
        case .conflict(let serverRecord): serverRecord.id.zone
        case .unknownItem(let id), .quotaExceeded(let id), .permission(let id), .other(let id, _): id.zone
        case .zoneMissing(let zone): zone
        }
    }
}

extension PendingChange {
    var recordID: CloudRecordID {
        switch self {
        case .save(let id), .delete(let id): id
        }
    }
}
