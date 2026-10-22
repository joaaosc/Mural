import Foundation
import MuralKit
import Observation

/// Lembretes em memória, para testes e para os testes de interface.
@MainActor
@Observable
final class FakeReminders: RemindersProviding {
    struct Failure: Error {}

    var access: RemindersAccess
    private(set) var changeCount = 0
    /// Quando `true`, `setCompleted` lança erro.
    var failsToComplete = false
    /// Quando `true`, `access` passa a `granted` ao pedir.
    var grantsOnRequest = true

    private(set) var storedLists: [ReminderList] = [
        ReminderList(id: "casa", title: "Casa", colorHex: "#FF9500"),
        ReminderList(id: "trabalho", title: "Trabalho", colorHex: "#007AFF"),
    ]
    private(set) var storage: [String: [ReminderSnapshot]] = [:]

    // Registro das chamadas.
    private(set) var requestAccessCalls = 0
    private(set) var lookupCalls = 0
    private(set) var setCompletedCalls: [(identifier: String, completed: Bool)] = []
    private(set) var openedIdentifiers: [String] = []

    init(access: RemindersAccess = .granted) {
        self.access = access
        storage["casa"] = [
            Self.make("casa-1", "Comprar pão", list: storedLists[0]),
            Self.make("casa-2", "Pagar a luz", list: storedLists[0], completed: true),
        ]
        storage["trabalho"] = [
            Self.make("trab-1", "Enviar relatório", list: storedLists[1]),
            Self.make("trab-2", "Marcar reunião", list: storedLists[1]),
        ]
    }

    private static func make(
        _ id: String, _ title: String, list: ReminderList, completed: Bool = false
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            identifier: id, externalIdentifier: "ext-\(id)", title: title, isCompleted: completed,
            completionDate: completed ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
            listTitle: list.title, listColorHex: list.colorHex)
    }

    // MARK: Ajustes de teste

    /// Todos os lembretes, de todas as listas.
    var all: [ReminderSnapshot] { storedLists.flatMap { storage[$0.id] ?? [] } }

    /// Simula uma mudança feita no app Lembretes.
    func simulateChange() { changeCount += 1 }

    /// Troca um lembrete (pelo identificador) e simula a mudança.
    func replace(_ snapshot: ReminderSnapshot) {
        for key in storage.keys {
            if let index = storage[key]?.firstIndex(where: { $0.identifier == snapshot.identifier }) {
                storage[key]?[index] = snapshot
            }
        }
        simulateChange()
    }

    /// Apaga um lembrete e simula a mudança.
    func remove(identifier: String) {
        for key in storage.keys { storage[key]?.removeAll { $0.identifier == identifier } }
        simulateChange()
    }

    // MARK: RemindersProviding

    func requestAccess() async -> RemindersAccess {
        requestAccessCalls += 1
        if access == .notDetermined { access = grantsOnRequest ? .granted : .denied }
        return access
    }

    func lists() -> [ReminderList] { access == .granted ? storedLists : [] }

    func reminders(inList listID: String, includingCompleted: Bool) async -> [ReminderSnapshot] {
        guard access == .granted else { return [] }
        return (storage[listID] ?? []).filter { includingCompleted || !$0.isCompleted }
    }

    func lookup(_ snapshot: ReminderSnapshot) async -> ReminderLookup {
        lookupCalls += 1
        guard access == .granted else { return .unavailable }
        if let found = all.first(where: { $0.identifier == snapshot.identifier }) { return .found(found) }
        return .missing
    }

    func setCompleted(_ completed: Bool, for snapshot: ReminderSnapshot) async throws -> ReminderSnapshot {
        setCompletedCalls.append((snapshot.identifier, completed))
        guard !failsToComplete, access == .granted,
            var current = all.first(where: { $0.identifier == snapshot.identifier })
        else { throw Failure() }
        current.isCompleted = completed
        current.completionDate = completed ? .now : nil
        replace(current)
        return current
    }

    func open(_ snapshot: ReminderSnapshot) { openedIdentifiers.append(snapshot.identifier) }
}
