import SwiftUI

/// A barra de tempo do Tocando agora: arrastável, com o tempo tocado à esquerda e o que falta à direita.
///
/// Enquanto a pessoa arrasta, a barra mostra o valor arrastado; a busca só vai ao tocador ao soltar. Fora disso, lê a
/// posição do tocador a cada meio segundo (parado, a leitura só muda quando a view se redesenha, por exemplo depois de
/// uma busca).
struct NowPlayingScrubber: View {
    let duration: TimeInterval
    let isPlaying: Bool
    let elapsed: () -> TimeInterval
    let seek: (TimeInterval) -> Void
    let id: String

    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.5, paused: !isPlaying && dragValue == nil)) { _ in
            let current = dragValue ?? min(max(elapsed(), 0), duration)
            VStack(spacing: 0) {
                Slider(
                    value: Binding(get: { current }, set: { dragValue = $0 }), in: 0...duration,
                    onEditingChanged: { editing in
                        guard !editing, let value = dragValue else { return }
                        seek(value)
                        dragValue = nil
                    }
                )
                .controlSize(.small)
                .accessibilityLabel("Posição na faixa")
                .accessibilityValue("\(NowPlayingTime.spoken(current)) de \(NowPlayingTime.spoken(duration))")
                .accessibilityIdentifier(id)
                HStack {
                    Text(NowPlayingTime.format(current))
                    Spacer()
                    Text("-" + NowPlayingTime.format(duration - current))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
        }
    }
}

/// Formatação dos tempos de uma faixa.
enum NowPlayingTime {
    /// `m:ss`, ou `h:mm:ss` a partir de uma hora.
    static func format(_ time: TimeInterval) -> String {
        let total = Int(max(time, 0).rounded(.down))
        let (hours, minutes, seconds) = (total / 3600, total % 3600 / 60, total % 60)
        if hours > 0 { return "\(hours):\(pad(minutes)):\(pad(seconds))" }
        return "\(minutes):\(pad(seconds))"
    }

    /// Para a leitura em voz alta: "1 minuto e 5 segundos".
    static func spoken(_ time: TimeInterval) -> String {
        Duration.seconds(Int(max(time, 0))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : "\(value)" }
}
