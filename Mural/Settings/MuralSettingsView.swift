import SwiftUI

/// A janela de Ajustes do Mural (cena `Settings`): uma aba por assunto, como os Ajustes dos apps do macOS.
///
/// A aba escolhida fica guardada: a janela reabre onde a pessoa estava.
struct MuralSettingsView: View {
    @AppStorage("settingsTab") private var selection: SettingsTab = .general
    /// As cópias no iCloud Drive; `nil` sem iCloud Drive.
    private let driveMirror: DriveMirrorController?

    init(driveMirror: DriveMirrorController? = nil) {
        self.driveMirror = driveMirror
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(SettingsTab.general.title, systemImage: SettingsTab.general.symbolName, value: .general) {
                GeneralSettingsView(loginItem: .shared, driveMirror: driveMirror)
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
