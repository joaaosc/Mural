import Foundation
import Testing

@testable import MuralKit

@MainActor
@Suite("Cartão de lembrete")
struct ReminderCardTests {
    private func makeStore() -> BoardStore {
        BoardStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("MuralReminder-\(UUID().uuidString)"))
    }

    private func snapshot(_ id: String = "R1", title: String = "Comprar pão") -> ReminderSnapshot {
        ReminderSnapshot(
            identifier: id, title: title, notes: "Integral", dueDate: Date(timeIntervalSince1970: 1_800_000_000), dueHasTime: true,
            priority: 1, listTitle: "Casa", listColorHex: "#FF9500")
    }

    private func assertPackageError(_ board: Board, _ expected: BoardPortablePackageError) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MuralReminderPkg-\(UUID().uuidString)")
        let items = root.appendingPathComponent("Items", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        do {
            try await service.validateBoard(board, itemsURL: items)
            Issue.record("esperado \(expected), a validação passou")
        } catch {
            #expect((error as? BoardPortablePackageError) == expected)
        }
    }

    @Test("Cartões soltos e dentro de pasta, um por lembrete")
    func createsCards() {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let loose = model.addReminders([snapshot("A"), snapshot("B", title: "Pagar conta")])
        #expect(loose.count == 2)
        #expect(loose.map(\.title) == ["Comprar pão", "Pagar conta"])
        #expect(loose.allSatisfy { $0.kind == .reminder && $0.fileName == nil && $0.parentID == nil })
        let size = BoardLayout.cardSize(for: .reminder)
        #expect(!BoardLayout.overlaps(loose[0].position, size, loose[1].position, size, gap: 0))

        let folder = model.createFolder(named: "Casa")
        let inside = model.addReminders([snapshot("C")], into: folder.id)
        #expect(inside.first?.parentID == folder.id)
        #expect(model.addReminders([]).isEmpty)
        #expect(BoardModel(store: BoardStore(directory: store.directory), seedIfEmpty: false).reminderItems.count == 3)
    }

    @Test("Atualizar só grava quando muda, e o título acompanha")
    func updatesOnlyWhenChanged() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let item = try #require(model.addReminders([snapshot()]).first)
        #expect(model.updateReminder(item.id, with: snapshot()) == false)
        var changed = snapshot(title: "Comprar pão e leite")
        changed.isCompleted = true
        #expect(model.updateReminder(item.id, with: changed))
        #expect(model.item(id: item.id)?.title == "Comprar pão e leite")
        #expect(model.item(id: item.id)?.reminder?.isCompleted == true)
        #expect(model.updateReminder(item.id, with: changed) == false)
        let note = model.createNote()
        #expect(model.updateReminder(note.id, with: changed) == false)
    }

    @Test("Marcar como apagado mantém o último estado")
    func marksMissing() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let item = try #require(model.addReminders([snapshot()]).first)
        model.markReminderMissing(item.id)
        let reminder = try #require(model.item(id: item.id)?.reminder)
        #expect(reminder.isMissing)
        #expect(reminder.title == "Comprar pão")
    }

    @Test("reminderItems encontra cartões de qualquer nível")
    func reminderItemsAtAnyLevel() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let model = BoardModel(store: store, seedIfEmpty: false)
        let outer = model.createFolder(named: "Fora")
        let inner = try #require(model.createFolder(named: "Dentro", into: outer.id))
        model.addReminders([snapshot("A")])
        model.addReminders([snapshot("B")], into: outer.id)
        model.addReminders([snapshot("C")], into: inner.id)
        model.createNote()
        #expect(Set(model.reminderItems.compactMap { $0.reminder?.identifier }) == ["A", "B", "C"])
    }

    @Test("O filtro de tarefas inclui lembretes")
    func tasksFilter() {
        #expect(WorkspaceFilter.tasks.matches(.reminder))
        #expect(WorkspaceFilter.tasks.matches(.checklist))
        #expect(!WorkspaceFilter.notes.matches(.reminder))
        #expect(!ItemKind.reminder.storesFile)
    }

    @Test("A versão 6 só aparece com lembrete")
    func formatVersion() {
        #expect(Board.currentFormatVersion >= 6)
        #expect(Board(items: [BoardItem(kind: .sticky, title: "")]).requiredFormatVersion == 1)
        #expect(Board(items: [BoardItem(kind: .reminder, title: "x", reminder: snapshot())]).requiredFormatVersion == 6)
    }

    @Test("Ida e volta em JSON, e mural antigo sem o campo abre")
    func jsonRoundTrip() throws {
        let item = BoardItem(kind: .reminder, title: "Comprar pão", reminder: snapshot())
        let board = Board(items: [item])
        let data = try JSONEncoder().encode(board)
        let decoded = try JSONDecoder().decode(Board.self, from: data)
        #expect(decoded == board)
        #expect(decoded.items.first?.reminder == snapshot())

        let legacy = Data(
            """
            {"formatVersion":5,"items":[{"createdAt":0,"id":"5B0F4C2E-8C0B-4B1F-9D75-3E1A7F2A9C01","kind":"sticky","position":{"x":0,"y":0},"title":""}]}
            """.utf8)
        let old = try JSONDecoder().decode(Board.self, from: legacy)
        #expect(old.items.first?.reminder == nil)
    }

    @Test("O cartão de lembrete é baixo e largo, e nunca está em branco")
    func layoutAndBlank() {
        let size = BoardLayout.cardSize(for: .reminder)
        #expect(size.width == 160 && size.height == 96)
        let item = BoardItem(kind: .reminder, title: "", reminder: snapshot())
        #expect(BoardLayout.aspectRatio(for: item) == 1.6)
        #expect(!item.isBlank)
        #expect(NoteFolding.source(of: item) == nil)
    }

    @Test("A validação do pacote exige o estado do lembrete, sem arquivo e com textos razoáveis")
    func packageValidation() async throws {
        let id = UUID()
        let valid = BoardItem(id: id, kind: .reminder, title: "x", reminder: snapshot())
        let service = BoardPortablePackageService(availableCapacity: { _ in nil })
        let items = FileManager.default.temporaryDirectory.appendingPathComponent("MuralReminderOK-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: items) }
        try await service.validateBoard(Board(items: [valid]), itemsURL: items)

        try await assertPackageError(Board(items: [BoardItem(id: id, kind: .reminder, title: "x")]), .invalidReminder(id))
        try await assertPackageError(
            Board(items: [BoardItem(id: id, kind: .reminder, title: "x", fileName: "a.png", reminder: snapshot())]), .invalidReminder(id))
        var longNotes = snapshot()
        longNotes.notes = String(repeating: "a", count: 100_001)
        try await assertPackageError(
            Board(items: [BoardItem(id: id, kind: .reminder, title: "x", reminder: longNotes)]), .invalidReminder(id))
        var longTitle = snapshot()
        longTitle.title = String(repeating: "a", count: 1_001)
        try await assertPackageError(
            Board(items: [BoardItem(id: id, kind: .reminder, title: "x", reminder: longTitle)]), .invalidReminder(id))
    }
}
