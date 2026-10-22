import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Data do cartão de lembrete")
@MainActor
struct ReminderCardTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Sexta, 31 de outubro de 2025, 10:00.
    private var now: Date { date(2025, 10, 31, 10) }

    private func text(_ due: Date, hasTime: Bool = true) -> String {
        ReminderDueText.text(for: due, hasTime: hasTime, now: now, calendar: Self.calendar)
    }

    @Test("Hoje e amanhã, com e sem hora")
    func todayAndTomorrow() {
        #expect(text(date(2025, 10, 31, 14)) == "Hoje, 14:00")
        #expect(text(date(2025, 10, 31), hasTime: false) == "Hoje")
        #expect(text(date(2025, 11, 1, 9, 30)) == "Amanhã, 09:30")
        #expect(text(date(2025, 11, 1), hasTime: false) == "Amanhã")
    }

    @Test("Outro dia mostra o dia da semana, e o ano só quando muda")
    func otherDay() {
        #expect(text(date(2025, 11, 3), hasTime: false) == "seg., 3 nov.")
        #expect(text(date(2025, 11, 3, 8)) == "seg., 3 nov., 08:00")
        #expect(text(date(2026, 1, 5), hasTime: false) == "seg., 5 jan. 2026")
    }

    @Test("Atraso: com hora vale o instante, sem hora vale o dia")
    func overdue() {
        func overdue(_ due: Date, hasTime: Bool) -> Bool {
            ReminderDueText.isOverdue(due, hasTime: hasTime, now: now, calendar: Self.calendar)
        }
        #expect(overdue(date(2025, 10, 31, 9), hasTime: true))
        #expect(!overdue(date(2025, 10, 31, 11), hasTime: true))
        #expect(!overdue(date(2025, 10, 31), hasTime: false))
        #expect(overdue(date(2025, 10, 30), hasTime: false))
    }

    @Test("Marca de prioridade e cor da lista")
    func priorityAndColor() {
        func mark(_ priority: Int) -> String? {
            ReminderSnapshotFixture.make(priority: priority).priorityMark
        }
        #expect(mark(0) == nil)
        #expect(mark(1) == "!!!" && mark(4) == "!!!")
        #expect(mark(5) == "!!")
        #expect(mark(6) == "!" && mark(9) == "!")
    }
}

private enum ReminderSnapshotFixture {
    static func make(priority: Int) -> ReminderSnapshot {
        ReminderSnapshot(identifier: "x", title: "x", priority: priority)
    }
}
