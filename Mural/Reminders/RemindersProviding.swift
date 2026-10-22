import Foundation
import MuralKit

/// Situação da permissão de acesso ao app Lembretes.
enum RemindersAccess: Equatable, Sendable {
    case notDetermined
    case denied
    case granted
}

/// Uma lista do app Lembretes.
struct ReminderList: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    /// Cor da lista, no formato `#RRGGBB`.
    var colorHex: String?
}

/// Resultado de procurar de novo um lembrete já guardado num cartão.
enum ReminderLookup: Equatable {
    case found(ReminderSnapshot)
    /// O lembrete não existe mais.
    case missing
    /// Sem acesso ao Lembretes: não dá para saber.
    case unavailable
}

/// Ponte com o app Lembretes. Há uma versão real (EventKit) e uma falsa para testes.
@MainActor
protocol RemindersProviding: AnyObject {
    var access: RemindersAccess { get }
    /// Sobe sempre que o app Lembretes muda.
    var changeCount: Int { get }
    func requestAccess() async -> RemindersAccess
    func lists() -> [ReminderList]
    func reminders(inList listID: String, includingCompleted: Bool) async -> [ReminderSnapshot]
    func lookup(_ snapshot: ReminderSnapshot) async -> ReminderLookup
    func setCompleted(_ completed: Bool, for snapshot: ReminderSnapshot) async throws -> ReminderSnapshot
    func open(_ snapshot: ReminderSnapshot)
}
