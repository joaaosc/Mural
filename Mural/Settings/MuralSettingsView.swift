import SwiftUI

/// A janela de Ajustes do Mural (cena `Settings`): uma aba por assunto, como os Ajustes dos apps do macOS.
///
/// A aba escolhida fica guardada: a janela reabre onde a pessoa estava.
struct MuralSettingsView: View {
    @AppStorage("settingsTab") private var selection: SettingsTab = .general

    var body: some View {
        TabView(selection: $selection) {
            Tab(SettingsTab.general.title, systemImage: SettingsTab.general.symbolName, value: .general) {
                GeneralSettingsView(loginItem: .shared)
            }
            Tab(SettingsTab.panel.title, systemImage: SettingsTab.panel.symbolName, value: .panel) {
                PanelSettingsView(hotKeys: .shared, position: .shared)
            }
        }
        .frame(width: 500)
    }
}

#Preview("Ajustes") {
    MuralSettingsView()
}
