import SwiftUI

/// O alto da etapa de formatação: a maneira de colar escolhida e o mural ("Colar como Sticker em Casa"), com a dica do
/// ⇧Tab. O clique na linha volta às maneiras de colar, como o ⇧Tab.
struct ChosenOptionLine: View {
    let symbolName: String
    let text: String
    /// Volta às maneiras de colar.
    let goBack: @MainActor () -> Void

    var body: some View {
        Button(action: goBack) {
            HStack(spacing: 6) {
                Image(systemName: symbolName)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(text)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 12)
                KeyHint(symbol: "arrow.left.to.line", label: "Voltar", description: "Shift Tab volta às maneiras de colar")
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("⇧Tab: voltar às maneiras de colar")
        .accessibilityHint("Volta às maneiras de colar.")
        .accessibilityIdentifier("menu-bar-chosen-option")
    }
}
