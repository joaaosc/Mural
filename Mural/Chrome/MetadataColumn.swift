import SwiftUI

/// Pares rótulo/valor em monoespaçada pequena, como RESOLUTION / 1332 × 1788.
struct MetadataColumn: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.label) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label.uppercased())
                        .foregroundStyle(.tertiary)
                    Text(row.value.uppercased())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .font(.label)
    }
}

#Preview {
    MetadataColumn(rows: [
        ("Resolution", "1332 × 1788"), ("Size", "12 MB"), ("Date", "15 Aug 2025"), ("Color profile", "sRGB IEC61966-2.1"),
    ])
    .padding(40)
    .background(Theme.page)
}
