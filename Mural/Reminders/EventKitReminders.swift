import AppKit
import EventKit
import Foundation
import MuralKit
import Observation

/// Ponte real com o app Lembretes, pelo EventKit.
@MainActor
@Observable
final class EventKitReminders: RemindersProviding {
    struct ReminderNotFound: Error {}

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: NotificationCenter.ObservationToken?
    private(set) var changeCount = 0

    init() {
        observer = NotificationCenter.default.addObserver(of: store, for: .changed) { [weak self] _ in
            self?.changeCount += 1
        }
    }

    var access: RemindersAccess {
        // Lê o contador para a observação reavaliar depois de uma mudança.
        _ = changeCount
        return Self.map(EKEventStore.authorizationStatus(for: .reminder))
    }

    private static func map(_ status: EKAuthorizationStatus) -> RemindersAccess {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> RemindersAccess {
        _ = try? await store.requestFullAccessToReminders()
        changeCount += 1
        return access
    }

    func lists() -> [ReminderList] {
        guard access == .granted else { return [] }
        return store.calendars(for: .reminder).map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title, colorHex: Self.hex($0.cgColor))
        }
    }

    func reminders(inList listID: String, includingCompleted: Bool) async -> [ReminderSnapshot] {
        guard access == .granted, let calendar = store.calendar(withIdentifier: listID) else { return [] }
        let predicate = store.predicateForReminders(in: [calendar])
        let store = self.store
        let all: [ReminderSnapshot] = await withCheckedContinuation { continuation in
            // O EventKit chama a closure numa fila de fundo: nada isolado ao Main Actor aqui.
            store.fetchReminders(matching: predicate) { @Sendable reminders in
                continuation.resume(returning: (reminders ?? []).map { Self.snapshot(of: $0) })
            }
        }
        return includingCompleted ? all : all.filter { !$0.isCompleted }
    }

    func lookup(_ snapshot: ReminderSnapshot) async -> ReminderLookup {
        // Lembrete importado não tem identificador: procurar com texto vazio no EventKit seria um tiro no escuro.
        guard !snapshot.isDetached, access == .granted else { return .unavailable }
        guard let reminder = findReminder(snapshot) else { return .missing }
        return .found(Self.snapshot(of: reminder))
    }

    func setCompleted(_ completed: Bool, for snapshot: ReminderSnapshot) async throws -> ReminderSnapshot {
        guard !snapshot.isDetached, access == .granted, let reminder = findReminder(snapshot) else { throw ReminderNotFound() }
        reminder.isCompleted = completed
        try store.save(reminder, commit: true)
        return Self.snapshot(of: reminder)
    }

    func open(_ snapshot: ReminderSnapshot) {
        guard !snapshot.isDetached else { return }
        if let url = URL(string: "x-apple-reminderkit://REMCDReminder/\(snapshot.identifier)"),
            NSWorkspace.shared.open(url)
        {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Reminders.app"))
    }

    // MARK: Apoio

    /// Procura pelo identificador local; se ele se perdeu numa sincronização completa, pelo externo.
    private func findReminder(_ snapshot: ReminderSnapshot) -> EKReminder? {
        if !snapshot.identifier.isEmpty, let reminder = store.calendarItem(withIdentifier: snapshot.identifier) as? EKReminder {
            return reminder
        }
        if let external = snapshot.externalIdentifier {
            return store.calendarItems(withExternalIdentifier: external).lazy.compactMap { $0 as? EKReminder }.first
        }
        return nil
    }

    /// Converte fora do Main Actor: é chamada pela fila de fundo do EventKit.
    nonisolated static func snapshot(of reminder: EKReminder) -> ReminderSnapshot {
        let components = reminder.dueDateComponents
        let calendar = components?.calendar ?? Calendar.current
        return ReminderSnapshot(
            identifier: reminder.calendarItemIdentifier,
            externalIdentifier: reminder.calendarItemExternalIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes,
            dueDate: components.flatMap { calendar.date(from: $0) },
            dueHasTime: components?.hour != nil,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            priority: reminder.priority,
            listTitle: reminder.calendar?.title ?? "",
            listColorHex: reminder.calendar.flatMap { hex($0.cgColor) },
            url: reminder.url)
    }

    nonisolated static func hex(_ color: CGColor?) -> String? {
        guard let color, let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
            let c = srgb.components, c.count >= 3
        else { return nil }
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c[0]), byte(c[1]), byte(c[2]))
    }
}
