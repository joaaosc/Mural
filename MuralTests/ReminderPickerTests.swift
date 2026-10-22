import CoreGraphics
import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Escolha de lembretes")
@MainActor
struct ReminderPickerTests {
    private func snap(_ id: String, _ title: String, done: Bool = false) -> ReminderSnapshot {
        ReminderSnapshot(identifier: id, title: title, isCompleted: done, listTitle: "Casa")
    }

    /// Conclui a restauração do mural, como faz a tela, para a sessão aceitar conteúdo.
    private func makeReady(_ session: BoardWindowSession) throws {
        let metrics = CanvasScrollMetrics(
            contentOffset: .zero,
            containerSize: CGSize(width: 900, height: 700),
            contentSize: CGSize(width: 3_400, height: 2_800))
        session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: metrics)
        let reached = CanvasScrollMetrics(
            contentOffset: session.zoom.scrollRequest?.point ?? .zero,
            containerSize: metrics.containerSize,
            contentSize: metrics.contentSize,
            contentInsets: metrics.contentInsets)
        for _ in 0..<3 where session.restorationPhase != .ready {
            session.restoreCanvas(boardID: session.boardID, generation: session.presentationGeneration, metrics: reached)
        }
        #expect(session.restorationPhase == .ready)
    }

    @Test("Esconde concluídos e põe os pendentes primeiro")
    func order() {
        let all = [snap("1", "A", done: true), snap("2", "B"), snap("3", "C", done: true), snap("4", "D")]
        let hidden = ReminderPickerFilter.visible(all, query: "", showCompleted: false)
        #expect(hidden.map(\.identifier) == ["2", "4"])
        let shown = ReminderPickerFilter.visible(all, query: "", showCompleted: true)
        #expect(shown.map(\.identifier) == ["2", "4", "1", "3"])
    }

    @Test("A busca ignora maiúsculas e acentos")
    func search() {
        let all = [snap("1", "Reunião de equipe"), snap("2", "Comprar pão")]
        #expect(ReminderPickerFilter.visible(all, query: "reuniao", showCompleted: true).map(\.identifier) == ["1"])
        #expect(ReminderPickerFilter.visible(all, query: "  PÃO ", showCompleted: true).map(\.identifier) == ["2"])
        #expect(ReminderPickerFilter.visible(all, query: "xyz", showCompleted: true).isEmpty)
    }

    @Test("Adicionar os escolhidos cria os cartões na pasta aberta")
    func addCreatesCards() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MuralPicker-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = BoardLibrary(rootDirectory: directory)
        let route = try await library.createNamedBoard("Lembretes")
        let session = BoardWindowSession(route: route, registry: BoardSessionRegistry(library: library))
        let fake = FakeReminders()
        session.reminders = fake
        await session.load()
        try makeReady(session)
        let model = try #require(session.model)
        let snapshots = ReminderPickerFilter.visible(
            await fake.reminders(inList: "casa", includingCompleted: true), query: "", showCompleted: true)
        let ids = session.addReminders(snapshots)
        #expect(ids.count == snapshots.count)
        #expect(model.reminderItems.count == snapshots.count)
    }
}
