import SwiftUI

/// O seletor de paleta dos Ajustes: um botão de rádio por paleta, com três amostras (mural, página e papel) ao lado do nome.
struct ThemePalettePicker: View {
    let store: ThemeStore

    var body: some View {
        @Bindable var store = store
        Picker("Tema", selection: $store.palette) {
            ForEach(ThemePalette.allCases) { palette in
                HStack(spacing: 8) {
                    swatches(for: palette)
                    Text(palette.title)
                }
                .tag(palette)
                .accessibilityIdentifier("settings-theme-\(palette.rawValue)")
            }
        }
        .pickerStyle(.radioGroup)
        .accessibilityIdentifier("settings-theme")
    }

    private func swatches(for palette: ThemePalette) -> some View {
        let colors = palette.colors
        return HStack(spacing: 2) {
            ForEach([colors.canvas, colors.page, colors.paper], id: \.self) { color in
                Circle()
                    .fill(color)
                    .overlay(Circle().strokeBorder(.quaternary))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Seletor de tema") {
    Form {
        Section("Aparência") {
            ThemePalettePicker(store: ThemeStore(preferences: UserDefaults(suiteName: "preview-theme")!))
        }
    }
    .formStyle(.grouped)
    .frame(width: 500)
}
