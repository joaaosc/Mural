import SwiftUI

/// O selo de "tocando" ou "pausado" no canto de uma música embutida, como o botão do cartão solto. Só desenho: o estado é dito
/// pelo valor de acessibilidade do cartão, e tocar ou pausar é o toque no cartão todo.
struct EmbeddedCardPhaseBadge: View {
    let phase: MusicCardPhase

    var body: some View {
        ZStack {
            if phase == .loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: phase == .playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
            }
        }
        .frame(width: 26, height: 26)
        .background(.regularMaterial, in: .circle)
        .padding(6)
        .accessibilityHidden(true)
    }
}
