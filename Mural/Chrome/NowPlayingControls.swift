import SwiftUI

/// A fileira de controles: aleatório, anterior, tocar/pausar, próxima e repetir (e, opcionalmente, parar).
///
/// Serve ao cartão expandido e ao painel da barra de menus; cada um passa os seus identificadores e o tamanho.
struct NowPlayingControls: View {
    /// Os identificadores de acessibilidade de cada botão.
    struct IDs {
        let shuffle: String
        let previous: String
        let playPause: String
        let next: String
        let repeatMode: String
        let stop: String
    }

    let summary: NowPlayingSummary
    let actions: NowPlayingActions
    let ids: IDs
    /// Largura de cada botão; o tocar/pausar é um pouco maior.
    var buttonWidth: CGFloat = 40
    var showsStop = false
    /// Sem foco: o painel guarda as setas para a vitrine.
    var takesFocus = true

    var body: some View {
        HStack(spacing: 0) {
            shuffleButton
            button(
                "Faixa anterior", symbol: "backward.fill", id: ids.previous, isEnabled: summary.canSkipBackward,
                action: actions.previous)
            playPauseButton
            button("Próxima faixa", symbol: "forward.fill", id: ids.next, action: actions.next)
            repeatButton
            if showsStop {
                button("Parar", symbol: "xmark", id: ids.stop, action: actions.stop)
            }
        }
        .font(.body.weight(.medium))
    }

    private var shuffleButton: some View {
        let isOn = summary.shuffle == .songs
        return Button(action: actions.toggleShuffle) {
            Label("Aleatório", systemImage: "shuffle")
                .labelStyle(.iconOnly)
                .foregroundStyle(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: buttonWidth, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .focusDisabled(!takesFocus)
        .disabled(summary.shuffle == nil)
        .help("Aleatório")
        .accessibilityLabel("Aleatório")
        .accessibilityValue(isOn ? "Ligado" : "Desligado")
        .accessibilityIdentifier(ids.shuffle)
    }

    private var repeatButton: some View {
        let mode = summary.repeatMode ?? MusicRepeat.none
        return Button(action: actions.cycleRepeat) {
            Label("Repetir", systemImage: mode == .one ? "repeat.1" : "repeat")
                .labelStyle(.iconOnly)
                .foregroundStyle(mode == .none ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                .frame(width: buttonWidth, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .focusDisabled(!takesFocus)
        .disabled(summary.repeatMode == nil)
        .help("Repetir")
        .accessibilityLabel("Repetir")
        .accessibilityValue(modeValue)
        .accessibilityIdentifier(ids.repeatMode)
    }

    private var modeValue: String {
        switch summary.repeatMode ?? MusicRepeat.none {
        case .none: "Desligado"
        case .all: "Tudo"
        case .one: "Uma"
        }
    }

    private var playPauseButton: some View {
        let isLoading = summary.phase == .loading
        let title = isLoading ? "Carregando" : (summary.phase == .playing ? "Pausar" : "Tocar")
        return Button(action: actions.playPause) {
            Group {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Label(title, systemImage: summary.phase == .playing ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                }
            }
            .frame(width: buttonWidth + 8, height: 32)
            .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .focusDisabled(!takesFocus)
        .disabled(isLoading)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(ids.playPause)
    }

    private func button(
        _ title: String, symbol: String, id: String, isEnabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: buttonWidth, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .focusDisabled(!takesFocus)
        .disabled(!isEnabled)
        .help(title)
        .accessibilityIdentifier(id)
    }
}

extension View {
    /// Tira a view da ordem de foco quando `disabled`; senão deixa como está.
    @ViewBuilder
    fileprivate func focusDisabled(_ disabled: Bool) -> some View {
        if disabled { focusable(false) } else { self }
    }
}
