import MuralKit
import SwiftUI

/// Texto da data de um lembrete, em português. Funções puras: o relógio e o calendário entram por parâmetro.
enum ReminderDueText {
    /// "Hoje, 14:00", "Amanhã", "seg., 3 nov." (com o ano quando não é o atual). Sem hora quando `hasTime` é falso.
    static func text(for date: Date, hasTime: Bool, now: Date, calendar: Calendar) -> String {
        let time = hasTime ? format("HH:mm", date, calendar) : nil
        let day: String
        if calendar.isDate(date, inSameDayAs: now) {
            day = "Hoje"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            day = "Amanhã"
        } else {
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            day = format(sameYear ? "EEE, d MMM" : "EEE, d MMM y", date, calendar)
        }
        return time.map { "\(day), \($0)" } ?? day
    }

    /// Passou do prazo: com hora, o instante já ficou para trás; sem hora, o dia já acabou.
    static func isOverdue(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar) -> Bool {
        hasTime ? date < now : calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
    }

    private static func format(_ pattern: String, _ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

extension ReminderSnapshot {
    /// Marca de prioridade como no Lembretes: `!!!` alta (1 a 4), `!!` média (5), `!` baixa (6 a 9); nada sem prioridade.
    var priorityMark: String? {
        switch priority {
        case 1...4: "!!!"
        case 5: "!!"
        case 6...9: "!"
        default: nil
        }
    }

    /// Nome da prioridade por extenso.
    var priorityName: String? {
        switch priority {
        case 1...4: "Alta"
        case 5: "Média"
        case 6...9: "Baixa"
        default: nil
        }
    }

    /// Cor da lista (`#RRGGBB`); sem ela ou com valor inválido, a cor de destaque do sistema.
    var listColor: Color {
        let digits = listColorHex?.drop { $0 == "#" } ?? ""
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .accentColor }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    /// Data para mostrar e se já passou do prazo (só vale para lembrete pendente).
    func dueDescription(now: Date = .now, calendar: Calendar = .current) -> (text: String, isOverdue: Bool)? {
        guard let dueDate else { return nil }
        return (
            ReminderDueText.text(for: dueDate, hasTime: dueHasTime, now: now, calendar: calendar),
            !isCompleted && ReminderDueText.isOverdue(dueDate, hasTime: dueHasTime, now: now, calendar: calendar)
        )
    }
}

/// Lembrete em miniatura: bolinha na cor da lista, título, data, lista e prioridade.
/// As fontes são fixas, como nas outras miniaturas.
struct ReminderCard: View {
    let reminder: ReminderSnapshot
    var now: Date = .now

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            checkmark
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.system(size: 9, weight: .semibold))
                    .strikethrough(reminder.isCompleted)
                    .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                status
                Spacer(minLength: 0)
                listRow
            }
        }
        .paperSheet()
        .opacity(reminder.isMissing ? 0.55 : 1)
        .saturation(reminder.isMissing ? 0 : 1)
    }

    private var checkmark: some View {
        Circle()
            .strokeBorder(reminder.isMissing ? Color.secondary : reminder.listColor, lineWidth: 1)
            .background(Circle().fill(reminder.isCompleted && !reminder.isMissing ? reminder.listColor : .clear))
            .overlay {
                if reminder.isCompleted {
                    Image(systemName: "checkmark").font(.system(size: 5, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var status: some View {
        if reminder.isMissing {
            Text("Apagado no Lembretes").font(.system(size: 6.5, weight: .medium)).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 3) {
                if reminder.isDetached {
                    Text("Importado").font(.system(size: 6.5, weight: .medium)).foregroundStyle(.secondary)
                }
                if let due = reminder.dueDescription(now: now) {
                    Text(due.text)
                        .font(.system(size: 6.5, weight: .medium))
                        .foregroundStyle(due.isOverdue ? Color.red : .secondary)
                }
                if let mark = reminder.priorityMark {
                    Text(mark).font(.system(size: 6.5, weight: .bold)).foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private var listRow: some View {
        if !reminder.listTitle.isEmpty {
            HStack(spacing: 3) {
                Circle().fill(reminder.listColor).frame(width: 4, height: 4)
                Text(reminder.listTitle).font(.system(size: 6)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

#if DEBUG
private enum ReminderPreviewData {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func snapshot(
        _ title: String, due: TimeInterval?, completed: Bool = false, missing: Bool = false, priority: Int = 0
    ) -> ReminderSnapshot {
        ReminderSnapshot(
            identifier: title, title: title, dueDate: due.map { now.addingTimeInterval($0) }, dueHasTime: true,
            isCompleted: completed, priority: priority, listTitle: "Casa", listColorHex: "#FF9500", isMissing: missing)
    }
    static let all = [
        snapshot("Comprar pão e leite", due: 3_600, priority: 1),
        snapshot("Pagar o condomínio", due: -90_000),
        snapshot("Ligar para o dentista", due: -3_600, completed: true),
        snapshot("Revisar a planta", due: nil, missing: true),
    ]
}

private struct ReminderCardRow: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(ReminderPreviewData.all, id: \.identifier) { reminder in
                ReminderCard(reminder: reminder, now: ReminderPreviewData.now).frame(width: 160, height: 96)
            }
        }
        .padding(24)
        .background(Theme.canvas)
    }
}

#Preview("Estados, claro", traits: .fixedLayout(width: 720, height: 150)) {
    ReminderCardRow().preferredColorScheme(.light)
}

#Preview("Estados, escuro", traits: .fixedLayout(width: 720, height: 150)) {
    ReminderCardRow().preferredColorScheme(.dark)
}
#endif
