import Foundation

/// O que chegou do iCloud para um mural: cartões e textos livres gravados ou apagados por outras pessoas (os cartões na forma de
/// `SharedFieldPolicy.shared`) e a ordem de empilhamento conhecida de cada cartão.
public struct RemoteBoardChanges: Equatable, Sendable {
    /// Cartões criados ou alterados por outras pessoas, inteiros.
    public var savedItems: [BoardItem]
    /// Cartões apagados por outras pessoas. Apagar uma pasta lista também tudo que havia dentro dela.
    public var deletedItemIDs: Set<UUID>
    public var savedFreeTexts: [BoardFreeText]
    public var deletedFreeTextIDs: Set<UUID>
    /// O número de empilhamento de cada cartão (`StackingOrder`). Quem não tem número fica no fim da lista.
    public var layers: [UUID: Double]

    public init(
        savedItems: [BoardItem] = [],
        deletedItemIDs: Set<UUID> = [],
        savedFreeTexts: [BoardFreeText] = [],
        deletedFreeTextIDs: Set<UUID> = [],
        layers: [UUID: Double] = [:]
    ) {
        self.savedItems = savedItems
        self.deletedItemIDs = deletedItemIDs
        self.savedFreeTexts = savedFreeTexts
        self.deletedFreeTextIDs = deletedFreeTextIDs
        self.layers = layers
    }
}

/// O mural depois de juntar o que chegou do iCloud com o que a pessoa fez neste Mac.
public struct BoardMergeResult: Equatable, Sendable {
    public var board: Board
    /// Cada cópia de conflito criada, com o id do cartão original, para a pessoa saber onde foi parar o que ela escreveu.
    public var conflictCopies: [UUID: UUID]
    /// Os cartões que o conserto da estrutura levou ao mural (`Board.repairStructure`), na ordem em que ganharam posição.
    public var repairedItemIDs: [UUID]

    public init(board: Board, conflictCopies: [UUID: UUID] = [:], repairedItemIDs: [UUID] = []) {
        self.board = board
        self.conflictCopies = conflictCopies
        self.repairedItemIDs = repairedItemIDs
    }
}

/// Junta o que outras pessoas fizeram no mural com o que a pessoa fez neste Mac antes de ver as mudanças delas.
///
/// Dois Macs mexendo no mesmo cartão ao mesmo tempo é o caso comum, não a exceção, e nenhuma das duas pessoas deve perder o que
/// escreveu. Por isso a junção é campo a campo, e o que não dá para juntar (o mesmo trecho do texto, ou a mesma linha de uma lista)
/// fica numa cópia de conflito ao lado do cartão, em vez de um dos lados vencer em silêncio.
public enum BoardMerge {
    /// Quanto uma cópia de conflito se afasta do original, para não ficar escondida embaixo dele.
    private static let copyOffset = 24.0
    private static let copyTitleSuffix = " (cópia de conflito)"

    // MARK: Um cartão

    /// Junta as duas versões de um cartão que mudou nos dois lados, campo a campo, tendo como referência a `base`: o cartão como o
    /// iCloud o conhecia antes.
    ///
    /// - Campo que o local não mudou, vale o do remote; que o remote não mudou, o do local; mudado para o mesmo valor, ele.
    /// - Mudado dos dois jeitos, o texto passa pela `TextMerge`, a lista pela `ChecklistMerge` e os anexos se somam pelo nome do
    ///   arquivo (primeiro os do remote). Os outros campos ficam como no local, a última mudança a chegar ao iCloud.
    /// - Se o texto ou a lista colidem, o cartão fica com a versão do remote e o que o local escreveu vira uma cópia de conflito.
    /// - O título de um post-it acompanha o texto final sempre que o texto passa pela junção (juntado ou em colisão), como ao editar o
    ///   post-it; o de uma nota ou lista segue a regra dos campos.
    /// - Sem `base` (o cartão é novo para o iCloud), vale o local em tudo, sem cópia.
    ///
    /// Os cartões são comparados na forma `SharedFieldPolicy.shared`, e o resultado guarda as partes locais do cartão local.
    /// - Returns: o cartão junto e, se algo colidiu, a cópia de conflito com o conteúdo do local.
    public static func mergeItem(
        base: BoardItem?, local: BoardItem, remote: BoardItem, now: Date = .now
    ) -> (merged: BoardItem, conflictCopy: BoardItem?) {
        let mine = SharedFieldPolicy.shared(local)
        guard let base else { return (SharedFieldPolicy.preservingLocalFields(of: local, in: mine), nil) }

        let original = SharedFieldPolicy.shared(base)
        let theirs = SharedFieldPolicy.shared(remote)
        let changedHere = mine.changedFields(from: original)
        let changedThere = theirs.changedFields(from: original)
        let differing = mine.changedFields(from: theirs)

        // O que o local não mudou já vale o do remote, então a junção parte dele.
        var merged = theirs
        merged.id = local.id
        var collided = false
        var textWasMerged = false
        for field in BoardItem.Field.allCases where SharedFieldPolicy.scope(of: field) == .shared && changedHere.contains(field) {
            guard changedThere.contains(field), differing.contains(field) else {
                // Só o local mudou, ou os dois mudaram para o mesmo valor.
                assign(field, from: mine, to: &merged)
                continue
            }
            switch field {
            case .text:
                textWasMerged = true
                if let text = TextMerge.merge(base: original.text ?? "", local: mine.text ?? "", remote: theirs.text ?? "") {
                    merged.text = text.isEmpty ? nil : text
                } else {
                    collided = true
                }
            case .checklist:
                if let baseList = original.checklist, let localList = mine.checklist, let remoteList = theirs.checklist,
                    let list = ChecklistMerge.merge(base: baseList, local: localList, remote: remoteList)
                {
                    merged.checklist = list
                } else {
                    collided = true
                }
            case .attachments:
                var seen = Set<String>()
                let union = ((theirs.attachments ?? []) + (mine.attachments ?? [])).filter { seen.insert($0.fileName).inserted }
                merged.attachments = union.isEmpty ? nil : union
            default:
                assign(field, from: mine, to: &merged)
            }
        }
        if textWasMerged, merged.kind == .sticky { merged.title = stickyTitle(for: merged.text) }
        return (
            SharedFieldPolicy.preservingLocalFields(of: local, in: merged),
            collided ? conflictCopy(of: mine, now: now) : nil
        )
    }

    // MARK: O mural

    /// Aplica ao mural deste Mac o que outras pessoas fizeram, sem perder o que esta pessoa fez e o iCloud ainda não recebeu.
    ///
    /// `base` é o mural como o iCloud o conhecia antes desta mudança, com os cartões na forma `SharedFieldPolicy.shared`. Para cada
    /// cartão gravado por outra pessoa:
    /// - Se este Mac não o tem e o iCloud também não, é um cartão novo e entra.
    /// - Se este Mac o apagou e a base o tem, ele continua apagado. Mas se o texto ou a lista mudaram lá, o que chegou entra como
    ///   cópia de conflito, para ninguém perder o que escreveu.
    /// - Se o cartão daqui é igual ao da base (não há nada a enviar), vale o que chegou. Senão, os dois são juntos por `mergeItem`.
    ///
    /// Para cada cartão que outra pessoa apagou: sai daqui, a não ser que o texto ou a lista tenham mudado neste Mac, e então o
    /// cartão daqui vira uma cópia de conflito. Se um id vem gravado e apagado ao mesmo tempo, vale o apagado.
    ///
    /// Os textos livres seguem a mesma ideia, sem juntar por dentro: o apagado aqui continua apagado, o que mudou aqui fica como está
    /// e o resto vale o que chegou. Apagado por outra pessoa, sai.
    ///
    /// As cópias de conflito entram no fim da lista, por cima. Depois a lista segue a ordem dos números de empilhamento que
    /// chegaram (quem não tem número fica no fim, na ordem em que estava) e a estrutura é consertada (`Board.repairStructure`, que
    /// leva ao mural, por exemplo, o cartão que esta pessoa pôs numa pasta que outra apagou). Se o mural mudou de fato, a versão do
    /// formato passa a ser a que o conteúdo exige; se nada mudou, o mural volta idêntico ao daqui, com a versão que tinha.
    public static func apply(_ remote: RemoteBoardChanges, to local: Board, base: Board, now: Date = .now) -> BoardMergeResult {
        let localItems = firstByID(local.items)
        let baseItems = firstByID(base.items)

        var replacements: [UUID: BoardItem] = [:]
        var removals = Set<UUID>()
        var arrivals: [BoardItem] = []
        var copies: [BoardItem] = []
        var conflictCopies: [UUID: UUID] = [:]

        func keep(_ copy: BoardItem, of originalID: UUID) {
            copies.append(copy)
            conflictCopies[copy.id] = originalID
        }

        for saved in latestByID(remote.savedItems) where !remote.deletedItemIDs.contains(saved.id) {
            switch (localItems[saved.id], baseItems[saved.id]) {
            case (nil, nil):
                arrivals.append(SharedFieldPolicy.preservingLocalFields(of: nil, in: saved))
            case (nil, let original?):
                if differsInContent(saved, original) { keep(conflictCopy(of: saved, now: now), of: saved.id) }
            case (let mine?, let original):
                if let original, SharedFieldPolicy.shared(mine) == SharedFieldPolicy.shared(original) {
                    replacements[saved.id] = SharedFieldPolicy.preservingLocalFields(of: mine, in: saved)
                } else {
                    let result = mergeItem(base: original, local: mine, remote: saved, now: now)
                    replacements[saved.id] = result.merged
                    if let copy = result.conflictCopy { keep(copy, of: saved.id) }
                }
            }
        }

        // Em ordem fixa, para as cópias nascerem sempre na mesma ordem.
        for id in remote.deletedItemIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let mine = localItems[id] else { continue }
            removals.insert(id)
            if let original = baseItems[id], differsInContent(mine, original) { keep(conflictCopy(of: mine, now: now), of: id) }
        }

        var items = local.items.filter { !removals.contains($0.id) }.map { replacements[$0.id] ?? $0 }
        items += arrivals + copies

        var board = local
        board.items = stacked(items, layers: remote.layers)
        board.freeTexts = mergedFreeTexts(remote, local: local, base: base)
        let repaired = board.repairStructure()
        // Um mural antigo só muda de versão junto com uma mudança de fato (cartão, texto livre, cópia, conserto ou ordem).
        if board.items != local.items || board.freeTexts != local.freeTexts {
            board.formatVersion = board.requiredFormatVersion
        }
        return BoardMergeResult(board: board, conflictCopies: conflictCopies, repairedItemIDs: repaired)
    }

    // MARK: Interno

    /// Os textos livres daqui com o que chegou. Cada texto livre é um valor só, sem junção por dentro.
    private static func mergedFreeTexts(_ remote: RemoteBoardChanges, local: Board, base: Board) -> [BoardFreeText] {
        var texts = local.freeTexts
        let baseTexts = firstByID(base.freeTexts)
        var indexByID: [UUID: Int] = [:]
        for (index, text) in texts.enumerated() where indexByID[text.id] == nil { indexByID[text.id] = index }

        for saved in latestByID(remote.savedFreeTexts) where !remote.deletedFreeTextIDs.contains(saved.id) {
            if let index = indexByID[saved.id] {
                // Se o texto mudou aqui desde a base, fica o daqui; se não mudou, ou a base não o conhecia, vale o que chegou.
                if let original = baseTexts[saved.id], texts[index] != original { continue }
                texts[index] = saved
            } else if baseTexts[saved.id] == nil {
                // Sem o texto aqui e sem ele na base é um texto novo; com ele na base, foi apagado aqui e continua apagado.
                indexByID[saved.id] = texts.count
                texts.append(saved)
            }
        }
        texts.removeAll { remote.deletedFreeTextIDs.contains($0.id) }
        return texts
    }

    /// A lista na ordem de empilhamento dos números do iCloud. Quem não tem número fica no fim, na ordem em que estava.
    private static func stacked(_ items: [BoardItem], layers: [UUID: Double]) -> [BoardItem] {
        var pending = Dictionary(grouping: items, by: \.id).mapValues { ArraySlice($0) }
        return StackingOrder.sorted(items.map(\.id), layers: layers).compactMap { pending[$0]?.popFirst() }
    }

    /// O texto ou a lista são o que as pessoas escrevem; é a diferença neles que não pode se perder em silêncio.
    private static func differsInContent(_ lhs: BoardItem, _ rhs: BoardItem) -> Bool {
        lhs.text != rhs.text || lhs.checklist != rhs.checklist
    }

    /// O título de um post-it para o texto dado, como em `BoardModel.updateSticky`: a primeira linha, ou vazio sem texto.
    private static func stickyTitle(for text: String?) -> String {
        let body = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.isEmpty ? "" : ContentClassifier.title(forText: body)
    }

    /// Uma cópia do conteúdo do cartão (a forma `shared`), com id novo, criada agora, na mesma pasta e um pouco deslocada para não
    /// ficar escondida embaixo do original. O título de um post-it segue o texto, então fica como está.
    private static func conflictCopy(of item: BoardItem, now: Date) -> BoardItem {
        var copy = SharedFieldPolicy.shared(item)
        copy.id = UUID()
        copy.createdAt = now
        if copy.kind != .sticky { copy.title += copyTitleSuffix }
        if copy.parentID == nil { copy.position = BoardLayout.clamped(shifted(copy.position)) }
        if let place = copy.folderPosition { copy.folderPosition = shifted(place) }
        return copy
    }

    private static func shifted(_ point: BoardPoint) -> BoardPoint {
        BoardPoint(x: point.x + copyOffset, y: point.y + copyOffset)
    }

    /// Indexa por id; com id repetido (dado corrompido) vale o primeiro, como em `Board.item(id:)`.
    private static func firstByID<Element: Identifiable>(_ elements: [Element]) -> [UUID: Element] where Element.ID == UUID {
        Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Sem repetir ids: cada um na posição da primeira vez que aparece e com o valor da última, a gravação mais nova.
    private static func latestByID<Element: Identifiable>(_ elements: [Element]) -> [Element] where Element.ID == UUID {
        var latest: [UUID: Element] = [:]
        var order: [UUID] = []
        for element in elements {
            if latest.updateValue(element, forKey: element.id) == nil { order.append(element.id) }
        }
        return order.compactMap { latest[$0] }
    }

    /// Copia um campo de um cartão para outro. O `switch` é exaustivo de propósito: um campo novo de `BoardItem.Field` não compila
    /// até ser copiado aqui.
    private static func assign(_ field: BoardItem.Field, from source: BoardItem, to target: inout BoardItem) {
        switch field {
        case .kind: target.kind = source.kind
        case .title: target.title = source.title
        case .createdAt: target.createdAt = source.createdAt
        case .parentID: target.parentID = source.parentID
        case .position: target.position = source.position
        case .fileName: target.fileName = source.fileName
        case .text: target.text = source.text
        case .caption: target.caption = source.caption
        case .checklist: target.checklist = source.checklist
        case .stickyColor: target.stickyColor = source.stickyColor
        case .imageMetadata: target.imageMetadata = source.imageMetadata
        case .tag: target.tag = source.tag
        case .keySentences: target.keySentences = source.keySentences
        case .link: target.link = source.link
        case .reminder: target.reminder = source.reminder
        case .music: target.music = source.music
        case .colorTag: target.colorTag = source.colorTag
        case .attachments: target.attachments = source.attachments
        case .folderPosition: target.folderPosition = source.folderPosition
        }
    }
}
