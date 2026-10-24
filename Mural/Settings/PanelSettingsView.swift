import SwiftUI

/// A aba Painel dos Ajustes: o atalho que abre o painel da barra de menus de qualquer app e o lugar onde ele abre.
struct PanelSettingsView: View {
    let hotKeys: PanelHotKeyCenter
    let position: MenuBarPanelPosition

    var body: some View {
        @Bindable var position = position
        Form {
            Section {
                HotKeyRecorderView(center: hotKeys)
            } header: {
                Text("Atalho")
            } footer: {
                Text(
                    "Abre e fecha o painel de qualquer app. Se o macOS já usar a combinação (como o ⌘` de "
                        + "\"Mover o foco para a próxima janela\", em Teclado › Atalhos de Teclado), desligue-a lá ou "
                        + "escolha outra.")
            }

            Section {
                Toggle("Lembrar onde o painel foi deixado", isOn: $position.remembersPosition)
                    .accessibilityIdentifier("settings-remember-position")
                Button("Voltar o painel para junto do ícone", action: position.forget)
                    .disabled(position.savedTopLeft == nil)
                    .accessibilityIdentifier("settings-reset-position")
            } header: {
                Text("Posição")
            } footer: {
                Text("Arraste o painel pelo fundo para mudá-lo de lugar; ele abre ali da próxima vez.")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview("Painel") {
    PanelSettingsView(hotKeys: PanelHotKeyCenter(isEnabled: false), position: MenuBarPanelPosition())
        .frame(width: 500)
}
