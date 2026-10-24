import Foundation

/// O que mudou entre duas versões do mural, na medida em que o iCloud guarda: cartão a cartão e campo a campo, texto livre a texto
/// livre, e os arquivos de `Items/` que passaram a ser citados ou deixaram de ser. Assim cada gravação envia só o que mudou.
///
/// Mudança só de ordem na lista não entra: quem cuida dela é o `StackingOrder`.
public struct BoardChanges: Equatable, Sendable {
    /// Cartões criados (com todos os campos) ou alterados (só com os campos que mudaram).
    public var savedItems: [UUID: Set<BoardItem.Field>]
    /// Cartões que deixaram de existir. Apagar uma pasta lista também tudo que havia dentro dela.
    public var deletedItemIDs: Set<UUID>
    /// Textos livres criados ou alterados; o texto livre inteiro é comparado.
    public var savedFreeTextIDs: Set<UUID>
    public var deletedFreeTextIDs: Set<UUID>
    /// Arquivos de `Items/` que algum cartão cita agora e nenhum citava antes.
    public var addedFileNames: Set<String>
    /// Arquivos de `Items/` que algum cartão citava antes e nenhum cita agora; um arquivo que outro cartão ainda cita não entra.
    public var releasedFileNames: Set<String>

    public init(
        savedItems: [UUID: Set<BoardItem.Field>] = [:],
        deletedItemIDs: Set<UUID> = [],
        savedFreeTextIDs: Set<UUID> = [],
        deletedFreeTextIDs: Set<UUID> = [],
        addedFileNames: Set<String> = [],
        releasedFileNames: Set<String> = []
    ) {
        self.savedItems = savedItems
        self.deletedItemIDs = deletedItemIDs
        self.savedFreeTextIDs = savedFreeTextIDs
        self.deletedFreeTextIDs = deletedFreeTextIDs
        self.addedFileNames = addedFileNames
        self.releasedFileNames = releasedFileNames
    }

    /// Nada mudou.
    public var isEmpty: Bool {
        savedItems.isEmpty && deletedItemIDs.isEmpty && savedFreeTextIDs.isEmpty && deletedFreeTextIDs.isEmpty
            && addedFileNames.isEmpty && releasedFileNames.isEmpty
    }

    /// As mudanças que levam `old` a `new`.
    public static func between(_ old: Board, _ new: Board) -> BoardChanges {
        var changes = BoardChanges()

        let oldItems = firstByID(old.items)
        let newItems = firstByID(new.items)
        for (id, item) in newItems {
            guard let before = oldItems[id] else {
                changes.savedItems[id] = Set(BoardItem.Field.allCases)
                continue
            }
            let fields = item.changedFields(from: before)
            if !fields.isEmpty { changes.savedItems[id] = fields }
        }
        changes.deletedItemIDs = Set(oldItems.keys).subtracting(newItems.keys)

        let oldTexts = firstByID(old.freeTexts)
        let newTexts = firstByID(new.freeTexts)
        changes.savedFreeTextIDs = Set(newTexts.filter { oldTexts[$0.key] != $0.value }.keys)
        changes.deletedFreeTextIDs = Set(oldTexts.keys).subtracting(newTexts.keys)

        let oldNames = Set(old.items.flatMap(\.assetFileNames))
        let newNames = Set(new.items.flatMap(\.assetFileNames))
        changes.addedFileNames = newNames.subtracting(oldNames)
        changes.releasedFileNames = oldNames.subtracting(newNames)
        return changes
    }

    /// Indexa por id; com id repetido (dado corrompido) vale o primeiro, como em `Board.item(id:)`.
    private static func firstByID<Element: Identifiable>(_ elements: [Element]) -> [UUID: Element] where Element.ID == UUID {
        Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}
