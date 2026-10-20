import SwiftUI

/// Pares rótulo/valor ao lado da imagem (Resolução, Tamanho, Data, Perfil de cor).
struct MetadataColumn: View {
    let rows: [(label: String, value: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows, id: \.label) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .font(.callout)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    MetadataColumn(rows: [
        ("Resolução", "1332 × 1788"), ("Tamanho", "12 MB"), ("Data", "15/08/2025"), ("Perfil de cor", "sRGB IEC61966-2.1"),
    ])
    .padding(40)
    .background(Theme.page)
}
