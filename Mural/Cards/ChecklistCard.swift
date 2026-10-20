import MuralKit
import SwiftUI

/// Lista em miniatura: título e as primeiras linhas com bolinhas de marcação.
struct ChecklistCard: View {
    let document: ChecklistDocument

    private var previewEntries: [ChecklistEntry] {
        Array(document.sections.flatMap(\.entries).prefix(9))
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
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paper, in: .rect(cornerRadius: Theme.cardCorner))
        .cardShadow()
    }
}

#Preview {
    ChecklistCard(document: SampleBoard.thingsINeed)
        .frame(width: 120, height: 150)
        .padding(40)
        .background(Theme.canvas)
}
