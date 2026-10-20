import MuralKit
import SwiftUI

/// Lista "Things I need": título grande, texto de abertura e seções com itens marcáveis.
struct ChecklistDetailView: View {
    let item: BoardItem
    let model: BoardModel

    var body: some View {
        let document = item.checklist ?? ChecklistDocument(title: item.title, sections: [])
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(document.title)
                        .font(.system(size: 40, weight: .bold))
                    if !document.intro.isEmpty {
                        Text(document.intro)
                            .font(.body.weight(.medium))
                    }
                    let progress = document.progress
                    Text("\(progress.done) de \(progress.total) marcados")
                        .font(.label)
                        .foregroundStyle(.secondary)
                }
                ForEach(document.sections) { section in
                    VStack(alignment: .leading, spacing: 7) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.headline)
                                .padding(.bottom, 2)
                        }
                        ForEach(section.entries) { entry in
                            ChecklistRow(entry: entry) {
                                model.toggleChecklistEntry(entry.id, in: item.id)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.top, 100)
            .padding(.bottom, 110)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct ChecklistRow: View {
    let entry: ChecklistEntry
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: entry.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(entry.isDone ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                Text(entry.text)
                    .font(.reading)
                    .strikethrough(entry.isDone)
                    .foregroundStyle(entry.isDone ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(entry.text)
        .accessibilityValue(entry.isDone ? "Marcado" : "Não marcado")
        .accessibilityAddTraits(.isToggle)
    }
}
