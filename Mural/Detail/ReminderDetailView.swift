import AppKit
import MuralKit
import SwiftUI

/// Página de um lembrete: título grande, estado, data, prioridade, lista, notas e link.
/// Mostra o último estado guardado; a ligação com o app Lembretes vem depois.
struct ReminderDetailView: View {
    let item: BoardItem

    var body: some View {
        let reminder = item.reminder
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text(reminder?.title ?? item.title)
                    .font(.system(size: 40, weight: .bold))
                    .strikethrough(reminder?.isCompleted == true)
                    .textSelection(.enabled)
                if let reminder {
                    if reminder.isMissing {
                        Label("Apagado no Lembretes", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                    details(of: reminder)
                    if let notes = reminder.notes, !notes.isEmpty {
                        Text(notes).font(.reading).lineSpacing(5).textSelection(.enabled)
                    }
                    if let url = reminder.url {
                        Link(url.absoluteString, destination: url).lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 100)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity)
        }
        .discreetScrollIndicators()
    }

    private func details(of reminder: ReminderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                reminder.isCompleted ? "Concluído" : "A fazer",
                systemImage: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
            if let due = reminder.dueDescription() {
                Label(due.text, systemImage: "calendar").foregroundStyle(due.isOverdue ? Color.red : .primary)
            }
            if let name = reminder.priorityName {
                Label("Prioridade \(name.lowercased())", systemImage: "exclamationmark")
            }
            if !reminder.listTitle.isEmpty {
                Label {
                    Text(reminder.listTitle)
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(reminder.listColor)
                }
            }
        }
        .font(.callout)
    }
}
