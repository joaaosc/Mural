import Foundation

/// Último estado conhecido de um lembrete do app Lembretes, guardado no cartão.
public struct ReminderSnapshot: Codable, Hashable, Sendable {
    /// Identificador local do lembrete (`calendarItemIdentifier`).
    public var identifier: String
    /// Identificador que sobrevive entre aparelhos, quando existe.
    public var externalIdentifier: String?
    public var title: String
    public var notes: String?
    public var dueDate: Date?
    /// `false` quando o lembrete tem só o dia, sem hora.
    public var dueHasTime: Bool
    public var isCompleted: Bool
    public var completionDate: Date?
    /// Como no EventKit: 0 nenhuma, 1 a 4 alta, 5 média, 6 a 9 baixa.
    public var priority: Int
    public var listTitle: String
    /// Cor da lista, no formato `#RRGGBB`.
    public var listColorHex: String?
    public var url: URL?
    /// `true` quando o lembrete foi apagado no app Lembretes.
    public var isMissing: Bool

    /// Lembrete que veio num pacote de fora: sem identificador, não está ligado a nenhum lembrete do app Lembretes e só guarda
    /// o último estado. O app nunca o procura, marca ou abre.
    public var isDetached: Bool { identifier.isEmpty && externalIdentifier == nil }

    public init(
        identifier: String,
        externalIdentifier: String? = nil,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        dueHasTime: Bool = false,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        priority: Int = 0,
        listTitle: String = "",
        listColorHex: String? = nil,
        url: URL? = nil,
        isMissing: Bool = false
    ) {
        self.identifier = identifier
        self.externalIdentifier = externalIdentifier
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.priority = priority
        self.listTitle = listTitle
        self.listColorHex = listColorHex
        self.url = url
        self.isMissing = isMissing
    }
}
