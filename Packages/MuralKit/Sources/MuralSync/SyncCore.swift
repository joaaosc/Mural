import Foundation
import MuralKit

/// Uma mudança deste Mac que o iCloud ainda não tem.
public enum PendingChange: Hashable, Sendable {
    /// Gravar o registro com os valores atuais deste Mac (`SyncCore.record(for:state:local:name:itemsDirectory:)` o monta).
    case save(CloudRecordID)
    /// Apagar o registro do iCloud.
    case delete(CloudRecordID)
}

/// O que veio do iCloud, já incorporado ao estado, e o que sobra para quem chama aplicar ao mural e a `Items/`.
public struct ReceivedChanges: Equatable, Sendable {
    /// O que outras pessoas gravaram ou apagaram, para o `BoardMerge.apply`. `layers` traz todos os números de empilhamento de
    /// `BoardSyncState.layers` depois da mudança, não só os que chegaram: é com eles que a lista é reordenada.
    public var changes: RemoteBoardChanges
    /// A base antes desta mudança: a referência que o `BoardMerge.apply` pede para saber o que mudou aqui e o que mudou lá.
    public var previousBase: Board
    /// O nome novo do mural, se o registro do mural veio. Quem junta aplica `mergedName(local:)`, não este valor direto.
    public var name: String?
    /// O nome do mural na base antes desta mudança (`BoardSyncState.baseName`): é por ele que `mergedName(local:)` sabe se o nome
    /// daqui mudou desde então.
    public var previousBaseName: String?
    /// Os arquivos de mídia que chegaram: o nome em `Items/` e o arquivo temporário em que o iCloud o deixou, que quem chama copia.
    public var files: [String: URL]
    /// Os registros ilegíveis que foram ignorados, para quem chama registrar. Um deles não derruba os outros da leva.
    public var skippedRecordNames: [String]

    /// Não há o que aplicar ao mural nem o que copiar para `Items/`. Registro ignorado não conta: só resta registrá-lo.
    public var isEmpty: Bool {
        changes.savedItems.isEmpty && changes.deletedItemIDs.isEmpty && changes.savedFreeTexts.isEmpty
            && changes.deletedFreeTextIDs.isEmpty && name == nil && files.isEmpty
    }

    /// O nome que o mural fica tendo depois da junção, pela regra dos campos simples do cartão: o que chegou vale se o nome daqui
    /// ainda é o da base anterior (ou se não havia base); se a pessoa renomeou aqui desde então, o nome dela fica, continua
    /// pendente e vale a última mudança a chegar ao iCloud.
    public func mergedName(local: String) -> String {
        guard let name else { return local }
        guard let previousBaseName, local != previousBaseName else { return name }
        return local
    }

    public init(
        changes: RemoteBoardChanges = RemoteBoardChanges(),
        previousBase: Board = Board(),
        name: String? = nil,
        previousBaseName: String? = nil,
        files: [String: URL] = [:],
        skippedRecordNames: [String] = []
    ) {
        self.changes = changes
        self.previousBaseName = previousBaseName
        self.previousBase = previousBase
        self.name = name
        self.files = files
        self.skippedRecordNames = skippedRecordNames
    }
}

/// A regra de sincronização de um mural com o iCloud, em funções puras sobre o `BoardSyncState`.
///
/// Ela fica fora do CloudKit para que o motor de verdade e o iCloud falso dos testes usem exatamente a mesma conta: só muda quem
/// entrega e recebe os registros.
///
/// O princípio: um registro precisa ir ao iCloud quando o valor deste Mac (o cartão na forma `SharedFieldPolicy.shared`, com o seu
/// número de empilhamento) difere da base, que é o que o iCloud tem. Não há fila própria nem "o que mudou desde a última vez": a
/// diferença com a base é a fila. Assim o que chegou de outra pessoa e já foi juntado não volta ao iCloud (não há eco), e uma
/// mudança feita durante um envio continua pendente, porque a base só passa a ter o que o iCloud de fato aceitou.
public enum SyncCore {
    // MARK: O que falta enviar

    /// O que este Mac precisa gravar ou apagar no iCloud: a diferença entre o mural daqui e a base.
    ///
    /// - Cartões e textos livres: o que `BoardChanges` aponta entre a base e o mural daqui, mais os cartões cujo número de
    ///   empilhamento muda (`StackingOrder`).
    /// - O registro do mural: se o nome ou a versão do formato que o conteúdo exige difere do que o registro tem no iCloud
    ///   (`baseBoardFormatVersion`, e não a da base, que pode ter andado sem ele), ou se ele nunca foi enviado.
    /// - Mídia: arquivos que algum cartão cita, existem em `itemsDirectory` e ainda não subiram; e os que subiram e nenhum cartão cita
    ///   mais, se o dono (`mediaOwners`) não é de app mais novo. Sem dono conhecido, só se um cartão da base os citava: um arquivo que
    ///   chegou antes do seu cartão não pode passar por arquivo de cartão apagado.
    ///
    /// Um registro de app mais novo (`unsupportedRecordNames`, ou o mural com versão do formato que esta build não lê) nunca é
    /// gravado nem apagado, para não perder o que o app novo guardou.
    ///
    /// Vazio enquanto o mural espera a primeira busca (`BoardSyncState.isAwaitingFirstFetch`): o pacote daqui é provisório e vazio,
    /// com um nome que não é o do mural. Enviá-lo gravaria esse nome no registro do mural e o renomearia para todos.
    public static func pendingChanges(
        state: BoardSyncState,
        local: Board,
        name: String,
        itemsDirectory: URL,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Set<PendingChange> {
        guard !state.isAwaitingFirstFetch else { return [] }
        let zone = zoneID(of: state)
        var pending = Set<PendingChange>()
        func save(_ recordName: String) {
            guard !state.unsupportedRecordNames.contains(recordName) else { return }
            pending.insert(.save(CloudRecordID(zone: zone, name: recordName)))
        }
        func delete(_ recordName: String) {
            guard !state.unsupportedRecordNames.contains(recordName) else { return }
            pending.insert(.delete(CloudRecordID(zone: zone, name: recordName)))
        }

        var projected = local
        projected.items = local.items.map(SharedFieldPolicy.shared)
        let changes = BoardChanges.between(state.base, projected)

        for id in changes.savedItems.keys { save(id.uuidString) }
        for id in changes.deletedItemIDs { delete(id.uuidString) }
        for id in reassignedLayers(state: state, local: local).keys { save(id.uuidString) }
        for id in changes.savedFreeTextIDs { save(id.uuidString) }
        for id in changes.deletedFreeTextIDs { delete(id.uuidString) }

        if canWriteBoardRecord(state), state.baseName != name || state.baseBoardFormatVersion != local.requiredFormatVersion {
            save(CloudSchema.muralRecordName)
        }

        let cited = Set(local.items.flatMap(\.assetFileNames))
        // O nome do arquivo vira caminho em `Items/`: um nome que saísse da pasta nunca sobe.
        for file in cited where !state.uploadedFiles.contains(file) {
            guard BoardRepository.isSafeAssetName(file), fileExists(itemsDirectory.appendingPathComponent(file, isDirectory: false)) else {
                continue
            }
            save(file)
        }
        for file in state.uploadedFiles where !cited.contains(file) {
            if let owner = state.mediaOwners[file] {
                if !state.unsupportedRecordNames.contains(owner.uuidString) { delete(file) }
            } else if changes.releasedFileNames.contains(file) {
                delete(file)
            }
        }
        return pending
    }

    /// O registro a enviar para `id`, com os valores atuais deste Mac e os campos de sistema que o iCloud deu da última vez.
    ///
    /// O tipo vem de quem o nome representa aqui: o registro `mural`, um cartão, um texto livre ou um arquivo de `Items/`. Não gera
    /// registro o cartão de app mais novo (`unsupportedRecordNames`) nem o mural cuja versão do formato esta build não lê. Tampouco
    /// gera registro enquanto o mural espera a primeira busca (`BoardSyncState.isAwaitingFirstFetch`): o pacote é provisório, e o
    /// nome dele não pode chegar ao registro do mural no iCloud.
    /// - Returns: `nil` se o que o registro representa não existe mais aqui (a mudança some), se é de app mais novo ou se o mural
    ///   espera a primeira busca.
    /// - Throws: `CardRecordMappingError.recordTooLarge` se os campos do cartão passam do limite do iCloud.
    public static func record(
        for id: CloudRecordID, state: BoardSyncState, local: Board, name: String, itemsDirectory: URL
    ) throws -> CloudRecord? {
        guard !state.isAwaitingFirstFetch, !state.unsupportedRecordNames.contains(id.name) else { return nil }
        func build(_ type: CloudSchema.RecordType, _ fields: [String: CloudValue]) -> CloudRecord {
            CloudRecord(id: id, type: type.rawValue, fields: fields, systemFields: state.systemFields[id.name])
        }

        if id.name == CloudSchema.muralRecordName {
            return canWriteBoardRecord(state) ? build(.mural, CardRecordMapping.boardFields(name: name, board: local)) : nil
        }
        if let uuid = entityID(of: id.name) {
            if let index = local.items.firstIndex(where: { $0.id == uuid }) {
                // Sem número novo vale o que o iCloud já tem; sem nenhum dos dois (não deveria ocorrer), o lugar na lista.
                let layer = reassignedLayers(state: state, local: local)[uuid] ?? state.layers[uuid] ?? Double(index)
                let fields = try CardRecordMapping.fields(for: SharedFieldPolicy.shared(local.items[index]), layer: layer)
                return build(.card, fields)
            }
            if let freeText = local.freeText(id: uuid) { return build(.freeText, CardRecordMapping.fields(for: freeText)) }
        }

        guard BoardRepository.isSafeAssetName(id.name), let owner = local.items.first(where: { $0.assetFileNames.contains(id.name) })
        else { return nil }
        let file = itemsDirectory.appendingPathComponent(id.name, isDirectory: false)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return build(.mediaFile, CardRecordMapping.mediaFields(fileURL: file, cardID: owner.id))
    }

    // MARK: Depois de enviar

    /// O iCloud aceitou estes registros: a base passa a ter exatamente os valores enviados (o cartão e o seu número, o texto livre, o
    /// nome e a versão do formato do mural, o arquivo em `uploadedFiles` com o seu dono) e os campos de sistema que ele devolveu.
    /// Um registro que esta build não entende (app mais novo) não entra na base: fica só em `unsupportedRecordNames`.
    ///
    /// O que mudou aqui durante o envio não está nos registros e por isso continua pendente. Ou entra tudo, ou o estado fica como
    /// estava.
    /// - Throws: `CardRecordMappingError.invalidRecord` se um registro não pode ser lido. Os registros vêm de `record(for:...)`, então
    ///   isso é erro de quem chama.
    public static func confirmSaved(_ records: [CloudRecord], into state: inout BoardSyncState) throws {
        var updated = state
        for record in records { _ = try absorb(record, into: &updated, isOwnUpload: true) }
        updated.base.formatVersion = updated.base.requiredFormatVersion
        state = updated
    }

    /// O iCloud apagou estes registros: o que os nomes representam sai da base, dos números de empilhamento, de `uploadedFiles` (com o
    /// dono) e dos campos de sistema. Nome que não representa nada é ignorado.
    public static func confirmDeleted(_ ids: [CloudRecordID], into state: inout BoardSyncState) {
        for id in ids { forget(id.name, from: &state) }
        state.base.formatVersion = state.base.requiredFormatVersion
    }

    // MARK: O que chegou

    /// Incorpora ao estado o que veio do iCloud (o que foi buscado, ou a versão do servidor num conflito de gravação) e devolve o que
    /// falta aplicar ao mural daqui.
    ///
    /// A base e os números passam a ser os do iCloud. Quem chama junta o resultado com `BoardMerge.apply`, usando `previousBase`: o que
    /// esta pessoa mudou e o iCloud ainda não tem continua pendente, porque o mural junto difere da base nova. Um registro ilegível
    /// é ignorado (`skippedRecordNames`) e não derruba a leva; um de app mais novo vai para `unsupportedRecordNames` e nada mais muda
    /// nele. Registros apagados valem depois dos gravados, e o estado só muda se a leva toda passa.
    public static func receive(
        saved: [CloudRecord], deleted: [CloudRecordID], into state: inout BoardSyncState
    ) throws -> ReceivedChanges {
        var updated = state
        var received = ReceivedChanges(previousBase: state.base, previousBaseName: state.baseName)

        for record in saved {
            switch try readable(record, into: &updated) {
            case nil:
                received.skippedRecordNames.append(record.id.name)
            case .card(let item):
                upsert(item, into: &received.changes.savedItems)
            case .unsupported:
                break
            case .freeText(let freeText):
                upsert(freeText, into: &received.changes.savedFreeTexts)
            case .board(let name):
                received.name = name
            case .mediaFile(let fileName, let url):
                received.files[fileName] = url
            }
        }

        for id in deleted {
            let forgotten = forget(id.name, from: &updated)
            if let itemID = forgotten.itemID {
                received.changes.deletedItemIDs.insert(itemID)
                received.changes.savedItems.removeAll { $0.id == itemID }
            }
            if let freeTextID = forgotten.freeTextID {
                received.changes.deletedFreeTextIDs.insert(freeTextID)
                received.changes.savedFreeTexts.removeAll { $0.id == freeTextID }
            }
            received.files[id.name] = nil
            if id.name == CloudSchema.muralRecordName { received.name = nil }
        }

        updated.base.formatVersion = updated.base.requiredFormatVersion
        received.changes.layers = updated.layers
        state = updated
        return received
    }

    /// Lê o registro e o incorpora ao estado, ou devolve `nil` se está ilegível (nada muda).
    private static func readable(_ record: CloudRecord, into state: inout BoardSyncState) throws -> Absorbed? {
        do {
            return try absorb(record, into: &state, isOwnUpload: false)
        } catch CardRecordMappingError.invalidRecord {
            return nil
        }
    }

    // MARK: Interno

    /// O que um registro trouxe, já lido.
    private enum Absorbed {
        case card(BoardItem)
        case unsupported
        case freeText(BoardFreeText)
        case board(name: String)
        case mediaFile(fileName: String, url: URL)
    }

    /// Lê o registro e o põe no estado: a base, os números, o nome e a versão do mural, os arquivos enviados com os seus donos e os
    /// campos de sistema. Um registro de app mais novo só entra em `unsupportedRecordNames`; um que volta a ser entendido sai de lá. O
    /// registro é lido por inteiro antes de o estado mudar, então quem falha não deixa nada pela metade.
    ///
    /// O dono de um arquivo só é guardado se este Mac o conhece: um cartão da base ou de app mais novo, ou qualquer um quando o envio
    /// foi daqui (`isOwnUpload`). O arquivo que chega antes do seu cartão fica sem dono e ganha um quando o cartão chega; guardar o
    /// dono antes disso faria o arquivo parecer o de um cartão já apagado.
    /// - Throws: `CardRecordMappingError.invalidRecord` se o registro não pode ser lido.
    private static func absorb(_ record: CloudRecord, into state: inout BoardSyncState, isOwnUpload: Bool) throws -> Absorbed {
        let recordName = record.id.name
        let absorbed: Absorbed
        switch CloudSchema.RecordType(rawValue: record.type) {
        case .card?:
            switch try CardRecordMapping.card(from: record) {
            case .card(let item, let layer):
                upsert(item, into: &state.base.items)
                if let layer { state.layers[item.id] = layer }
                state.unsupportedRecordNames.remove(recordName)
                for file in item.assetFileNames where state.uploadedFiles.contains(file) && state.mediaOwners[file] == nil {
                    state.mediaOwners[file] = item.id
                }
                absorbed = .card(item)
            case .unsupported:
                state.unsupportedRecordNames.insert(recordName)
                absorbed = .unsupported
            }
        case .freeText?:
            switch try CardRecordMapping.freeText(from: record) {
            case .freeText(let freeText):
                upsert(freeText, into: &state.base.freeTexts)
                state.unsupportedRecordNames.remove(recordName)
                absorbed = .freeText(freeText)
            case .unsupported:
                state.unsupportedRecordNames.insert(recordName)
                absorbed = .unsupported
            }
        case .mural?:
            guard recordName == CloudSchema.muralRecordName, let name = CardRecordMapping.boardName(from: record) else {
                throw CardRecordMappingError.invalidRecord("o registro do mural precisa se chamar mural e ter nome: \(recordName)")
            }
            state.baseName = name
            state.baseBoardFormatVersion = CardRecordMapping.boardFormatVersion(from: record)
            absorbed = .board(name: name)
        case .mediaFile?:
            guard let file = CardRecordMapping.mediaFile(from: record) else {
                throw CardRecordMappingError.invalidRecord(
                    "o registro do arquivo não traz o arquivo ou o nome sai de Items/: \(recordName)")
            }
            state.uploadedFiles.insert(file.fileName)
            if let owner = CardRecordMapping.mediaCardID(from: record), isOwnUpload || isKnownCard(owner, in: state) {
                state.mediaOwners[file.fileName] = owner
            }
            absorbed = .mediaFile(fileName: file.fileName, url: file.url)
        case nil:
            throw CardRecordMappingError.invalidRecord("o tipo de registro é desconhecido: \(record.type)")
        }
        state.systemFields[recordName] = record.systemFields
        return absorbed
    }

    /// Tira do estado o que o nome representava. Devolve os ids que estavam na base como cartão ou texto livre, para `receive` contar.
    /// O dono de um arquivo sai junto com o arquivo, não com o cartão.
    @discardableResult
    private static func forget(_ recordName: String, from state: inout BoardSyncState) -> (itemID: UUID?, freeTextID: UUID?) {
        var forgotten: (itemID: UUID?, freeTextID: UUID?) = (nil, nil)
        if let id = entityID(of: recordName) {
            if state.base.items.contains(where: { $0.id == id }) {
                state.base.items.removeAll { $0.id == id }
                forgotten.itemID = id
            }
            if state.base.freeTexts.contains(where: { $0.id == id }) {
                state.base.freeTexts.removeAll { $0.id == id }
                forgotten.freeTextID = id
            }
            state.layers[id] = nil
        }
        // Sem o registro do mural no iCloud, o nome e a versão voltam a ser pendentes e ele é regravado.
        if recordName == CloudSchema.muralRecordName {
            state.baseName = nil
            state.baseBoardFormatVersion = nil
        }
        // O dono sai junto com o arquivo. Os donos que apontam para um cartão que saiu ficam: é por eles que o arquivo dele ainda pode
        // ser apagado, mesmo com o cartão já fora da base.
        state.mediaOwners[recordName] = nil
        state.uploadedFiles.remove(recordName)
        state.unsupportedRecordNames.remove(recordName)
        state.systemFields[recordName] = nil
        return forgotten
    }

    /// Os cartões cujo número de empilhamento muda, com o número novo. A mesma conta serve para saber o que enviar e para montar o
    /// registro, senão o número enviado não seria o que fez o cartão ficar pendente.
    private static func reassignedLayers(state: BoardSyncState, local: Board) -> [UUID: Double] {
        StackingOrder.assignments(for: local.items.map(\.id), previous: state.layers)
    }

    /// O registro do mural pode ser regravado? Não, se foi gravado por um app mais novo: a versão do formato dele cairia.
    private static func canWriteBoardRecord(_ state: BoardSyncState) -> Bool {
        (state.baseBoardFormatVersion ?? 0) <= Board.currentFormatVersion
    }

    /// Este Mac conhece o cartão: ele está na base ou é de um app mais novo.
    private static func isKnownCard(_ id: UUID, in state: BoardSyncState) -> Bool {
        state.base.items.contains { $0.id == id } || state.unsupportedRecordNames.contains(id.uuidString)
    }

    private static func zoneID(of state: BoardSyncState) -> CloudZoneID {
        CloudZoneID(name: state.cloud.zoneName, ownerName: state.cloud.zoneOwnerName)
    }

    /// O id de um cartão ou texto livre a partir do nome do registro. Só vale o `uuidString` canônico, o único que é produzido.
    private static func entityID(of recordName: String) -> UUID? {
        guard let id = UUID(uuidString: recordName), id.uuidString == recordName else { return nil }
        return id
    }

    /// Troca o elemento de mesmo id, ou o acrescenta no fim.
    private static func upsert<Element: Identifiable>(_ element: Element, into elements: inout [Element]) where Element.ID == UUID {
        if let index = elements.firstIndex(where: { $0.id == element.id }) {
            elements[index] = element
        } else {
            elements.append(element)
        }
    }
}
