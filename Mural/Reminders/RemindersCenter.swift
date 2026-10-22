/// Escolhe a ponte com o Lembretes: a falsa nos testes de interface, a do EventKit no uso normal.
@MainActor
enum RemindersCenter {
    static let shared: any RemindersProviding =
        LaunchConfiguration.isUITesting ? FakeReminders() : EventKitReminders()
}
