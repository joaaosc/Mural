import MuralKit
import SwiftUI

/// Lista em miniatura: título e as primeiras linhas com bolinhas de marcação.
struct ChecklistCard: View {
    let document: ChecklistDocument
    /// Cor da tag do cartão; tinge o papel sem deixá-lo transparente.
    var tint: TagColor? = nil

    private var previewEntries: [ChecklistEntry] {
        var entries: [ChecklistEntry] = []
        entries.reserveCapacity(9)
        for section in document.sections {
            for entry in section.entries {
                entries.append(entry)
                if entries.count == 9 { return entries }
            }
        }
        return entries
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(document.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(2)
                .padding(.bottom, 3)
            ForEach(previewEntries) { entry in
                HStack(spacing: 3) {
                    Circle()
                        .strokeBorder(.secondary, lineWidth: 0.5)
                        .background(Circle().fill(entry.isDone ? Color.accentColor : .clear))
                        .frame(width: 5, height: 5)
                    Text(entry.text)
                        .font(.system(size: 5.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .paperSheet(tint: tint?.color)
    }
}

#Preview {
    ChecklistCard(document: SampleBoard.thingsINeed)
        .frame(width: 120, height: 150)
        .padding(40)
        .background(Theme.canvas)
}

/// Três listas com tag de cor, lado a lado, para conferir quanto a cor tinge o papel.
private struct TintedChecklistCards: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach([TagColor.green, .purple, .orange]) { color in
                ChecklistCard(document: SampleBoard.thingsINeed, tint: color)
                    .frame(width: 120, height: 150)
            }
        }
        .padding(24)
        .background(Theme.canvas)
    }
}

#Preview("Com cor", traits: .fixedLayout(width: 460, height: 200)) {
    TintedChecklistCards()
}

#Preview("Com cor no escuro", traits: .fixedLayout(width: 460, height: 200)) {
    TintedChecklistCards()
        .preferredColorScheme(.dark)
}
