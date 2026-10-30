import EventKit
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Lembretes na sessão")
@MainActor
struct RemindersSessionTests {
    // MARK: Apoio

    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralReminders-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeReady(_ session: BoardWindowSession) async throws {
        await session.load()
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero,
            containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        // O alvo é o último pedido de rolagem da sessão (sem pedido, a origem).
        let target = session.zoom.scrollRequest?.point ?? .zero
        let reached = CanvasScrollMetrics(
            contentOffset: target,
            containerSize: metrics.containerSize,
            contentSize: metrics.contentSize,
            contentInsets: metrics.contentInsets)
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: reached)
        }
        #expect(session.restorationPhase == .ready)
    }

    private func makeSession(
        directory: URL, access: RemindersAccess = .granted
    ) async throws -> (BoardWindowSession, FakeReminders) {
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Lembretes")
        let registry = BoardSessionRegistry(library: library)
        let session = BoardWindowSession(route: route, registry: registry)
        let fake = FakeReminders(access: access)
        session.reminders = fake
        try await makeReady(session)
        return (session, fake)
    }

    private func firstSnapshot(_ fake: FakeReminders) async -> ReminderSnapshot {
        await fake.reminders(inList: "casa", includingCompleted: false).first!
    }

    // MARK: Sessão

    @Test("addReminders cria cartões na pasta aberta")
    func addInFolder() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        let folder = model.createFolder(named: "Pasta")
        session.setNavigation(path: [.collection(folder.id)], filter: nil)
        let snapshot = await firstSnapshot(fake)
        let ids = session.addReminders([snapshot])
        let id = try #require(ids.first)
        let item = try #require(model.item(id: id))
        #expect(item.kind == .reminder)
        #expect(item.parentID == folder.id)
    }

    @Test("refresh atualiza título e estado mudados no Lembretes")
    func refreshUpdates() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        var snapshot = await firstSnapshot(fake)
        let id = try #require(session.addReminders([snapshot]).first)
        snapshot.title = "Comprar pão integral"
        snapshot.isCompleted = true
        fake.replace(snapshot)
        await session.refreshReminders()
        let item = try #require(model.item(id: id))
        #expect(item.title == "Comprar pão integral")
        #expect(item.reminder?.isCompleted == true)
    }

    @Test("refresh marca como apagado o lembrete que sumiu")
    func refreshMissing() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        let snapshot = await firstSnapshot(fake)
        let id = try #require(session.addReminders([snapshot]).first)
        fake.remove(identifier: snapshot.identifier)
        await session.refreshReminders()
        #expect(model.item(id: id)?.reminder?.isMissing == true)
    }

    @Test("refresh sem acesso não muda nada")
    func refreshWithoutAccess() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        let snapshot = await firstSnapshot(fake)
        let id = try #require(session.addReminders([snapshot]).first)
        fake.remove(identifier: snapshot.identifier)
        fake.access = .denied
        await session.refreshReminders()
        #expect(model.item(id: id)?.reminder == snapshot)
    }

    @Test("toggle marca no Lembretes e no cartão")
    func toggleCompletes() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        let snapshot = await firstSnapshot(fake)
        let id = try #require(session.addReminders([snapshot]).first)
        await session.toggleReminder(id)
        #expect(fake.setCompletedCalls.map(\.completed) == [true])
        #expect(fake.all.first { $0.identifier == snapshot.identifier }?.isCompleted == true)
        #expect(model.item(id: id)?.reminder?.isCompleted == true)
        await session.toggleReminder(id)
        #expect(model.item(id: id)?.reminder?.isCompleted == false)
    }

    @Test("erro ao marcar mostra o aviso e preserva o cartão")
    func toggleFailure() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        let snapshot = await firstSnapshot(fake)
        let id = try #require(session.addReminders([snapshot]).first)
        fake.failsToComplete = true
        await session.toggleReminder(id)
        #expect(model.lastError == "Não foi possível marcar o lembrete no app Lembretes.")
        #expect(model.item(id: id)?.reminder?.isCompleted == false)
    }

    @Test("openReminder repassa o lembrete à ponte")
    func open() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let snapshot = await firstSnapshot(fake)
        let id = try #require(session.addReminders([snapshot]).first)
        session.openReminder(id)
        #expect(fake.openedIdentifiers == [snapshot.identifier])
    }

    @Test("lembrete importado fica como está: sem busca, sem marcar, sem abrir e sem virar apagado")
    func detachedReminderIsLeftAlone() async throws {
        let directory = try root()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (session, fake) = try await makeSession(directory: directory)
        let model = try #require(session.model)
        var detached = await firstSnapshot(fake)
        detached.identifier = ""
        detached.externalIdentifier = nil
        let id = try #require(session.addReminders([detached]).first)
        #expect(detached.isDetached)
        await session.refreshReminders()
        await session.toggleReminder(id)
        session.openReminder(id)
        #expect(fake.lookupCalls == 0)
        #expect(fake.setCompletedCalls.isEmpty)
        #expect(fake.openedIdentifiers.isEmpty)
        #expect(model.item(id: id)?.reminder == detached)
    }

    // MARK: Central e conversão

    @Test("RemindersCenter usa a versão falsa nos testes de interface")
    func center() {
        // Os testes hospedados não passam `-uiTesting`; só confere que a central existe sem acesso real.
        #expect(RemindersCenter.shared is FakeReminders == LaunchConfiguration.isUITesting)
    }

    @Test("EKReminder vira snapshot, com hora e sem hora")
    func conversion() {
        let reminder = EKReminder(eventStore: EKEventStore())
        reminder.title = "Ligar"
        reminder.notes = "Notas"
        reminder.priority = 5
        reminder.dueDateComponents = DateComponents(
            calendar: Calendar(identifier: .gregorian), year: 2030, month: 5, day: 4)
        var snapshot = EventKitReminders.snapshot(of: reminder)
        #expect(snapshot.title == "Ligar")
        #expect(snapshot.notes == "Notas")
        #expect(snapshot.priority == 5)
        #expect(snapshot.dueDate != nil)
        #expect(snapshot.dueHasTime == false)
        reminder.dueDateComponents = DateComponents(
            calendar: Calendar(identifier: .gregorian), year: 2030, month: 5, day: 4, hour: 9, minute: 30)
        snapshot = EventKitReminders.snapshot(of: reminder)
        #expect(snapshot.dueHasTime == true)
    }
}
