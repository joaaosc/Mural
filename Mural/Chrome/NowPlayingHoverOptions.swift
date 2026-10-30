import SwiftUI

/// As duas opções que surgem acima da cápsula do miniplayer quando o ponteiro fica parado sobre ele: levar a música para a
/// barra lateral ou pará-la e fechar o miniplayer.
///
/// Cada botão tem o próprio vidro, estático por trás de um botão sem borda (nunca `.interactive()`: ver o aviso em
/// `FloatingToolbar`), e mora no mesmo `GlassEffectContainer` da cápsula. O alinhamento e a entrada e a saída ficam com quem
/// as coloca (ver `NowPlayingPositioned`).
struct NowPlayingHoverOptions: View {
    /// Leva a música para a barra lateral.
    let moveToSidebar: () -> Void
    /// Para a música e fecha o miniplayer.
    let stop: () -> Void
    /// Reduzir Movimento: sem a transformação do vidro, só aparece e some.
    let reducesMotion: Bool

    var body: some View {
        HStack(spacing: 6) {
            option(
                "Barra lateral", symbol: "sidebar.left", help: "Levar para a barra lateral",
                id: "now-playing-option-sidebar", action: moveToSidebar)
            option(
                "Fechar", symbol: "xmark", help: "Parar a música e fechar o miniplayer",
                id: "now-playing-option-close", action: stop)
        }
    }

    private func option(
        _ title: String, symbol: String, help: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 12)
                .frame(height: 28)
                .contentShape(.capsule)
        }
        .buttonStyle(.borderless)
        .glassEffect(.regular, in: .capsule)
        .glassEffectTransition(reducesMotion ? .identity : .materialize)
        .help(help)
        .accessibilityIdentifier(id)
    }
}

#if DEBUG
private struct OptionsPreview: View {
    var body: some View {
        GlassEffectContainer(spacing: 0) {
            NowPlayingHoverOptions(moveToSidebar: {}, stop: {}, reducesMotion: false)
        }
        .padding(40)
        .background(Theme.canvas)
    }
}

#Preview("Opções") { OptionsPreview() }

#Preview("Opções, escuro") { OptionsPreview().preferredColorScheme(.dark) }
#endif
