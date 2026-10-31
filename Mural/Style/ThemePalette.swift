import AppKit
import Observation
import SwiftUI

/// As paletas de cor do app, escolhidas nos Ajustes. Cada uma define os fundos (mural, página) e o papel dos cartões,
/// com variante clara, escura e de alto contraste: claro e escuro continuam seguindo o sistema.
enum ThemePalette: String, CaseIterable, Identifiable, Sendable {
    /// Os cinzas de sempre.
    case neutral
    /// Areia e linho; no escuro, grafite com um toque âmbar.
    case warm
    /// Azul-gelo; no escuro, grafite azulado.
    case cool
    /// Sálvia; no escuro, musgo.
    case sage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neutral: "Neutro"
        case .warm: "Quente"
        case .cool: "Frio"
        case .sage: "Verde"
        }
    }

    /// Quanto da cor do mural cobre o material da janela: as paletas com matiz deixam a cor aparecer mais que o cinza.
    var boardTint: Double {
        self == .neutral ? 0.3 : 0.42
    }

    /// As cores de uma paleta, já dinâmicas (claro, escuro e alto contraste).
    struct Colors: Sendable {
        /// Fundo do mural e das coleções.
        let canvas: Color
        /// Tom mais fundo do mural, para o gradiente do fundo.
        let canvasDeep: Color
        /// Fundo das telas de detalhe e da barra lateral.
        let page: Color
        /// Papel dos cartões de texto.
        let paper: Color
        /// Folha de trás da pasta: entre o papel e o mural, opaca.
        let paperBack: Color
    }

    var colors: Colors { Self.colorsByPalette[self]! }

    /// As cores são montadas uma vez por paleta: `NSColor` dinâmico resolve claro, escuro e alto contraste na hora de desenhar.
    private static let colorsByPalette: [ThemePalette: Colors] = Dictionary(
        uniqueKeysWithValues: allCases.map { ($0, $0.makeColors()) })

    private func makeColors() -> Colors {
        switch self {
        case .neutral:
            Colors(
                canvas: Self.surface(light: (0.895, 0.902, 0.914), dark: (0.118, 0.122, 0.133)),
                canvasDeep: Self.surface(light: (0.858, 0.866, 0.880), dark: (0.092, 0.096, 0.106)),
                page: Self.surface(light: (0.957, 0.965, 0.976), dark: (0.090, 0.094, 0.102)),
                paper: Self.paper(light: (1, 1, 1), dark: (0.200, 0.204, 0.216)),
                paperBack: Self.paper(light: (0.984, 0.985, 0.987), dark: (0.188, 0.192, 0.204)))
        case .warm:
            Colors(
                canvas: Self.surface(light: (0.915, 0.885, 0.835), dark: (0.180, 0.165, 0.150)),
                canvasDeep: Self.surface(light: (0.870, 0.835, 0.775), dark: (0.140, 0.128, 0.115)),
                page: Self.surface(light: (0.962, 0.945, 0.915), dark: (0.150, 0.138, 0.125)),
                paper: Self.paper(light: (0.995, 0.985, 0.965), dark: (0.250, 0.232, 0.212)),
                paperBack: Self.paper(light: (0.980, 0.968, 0.945), dark: (0.230, 0.214, 0.196)))
        case .cool:
            Colors(
                canvas: Self.surface(light: (0.850, 0.880, 0.920), dark: (0.150, 0.165, 0.195)),
                canvasDeep: Self.surface(light: (0.795, 0.835, 0.890), dark: (0.110, 0.122, 0.150)),
                page: Self.surface(light: (0.935, 0.950, 0.970), dark: (0.125, 0.138, 0.165)),
                paper: Self.paper(light: (0.985, 0.990, 1.000), dark: (0.215, 0.230, 0.265)),
                paperBack: Self.paper(light: (0.965, 0.975, 0.990), dark: (0.200, 0.214, 0.246)))
        case .sage:
            Colors(
                canvas: Self.surface(light: (0.862, 0.895, 0.862), dark: (0.145, 0.170, 0.150)),
                canvasDeep: Self.surface(light: (0.810, 0.850, 0.810), dark: (0.105, 0.128, 0.110)),
                page: Self.surface(light: (0.940, 0.958, 0.940), dark: (0.122, 0.142, 0.126)),
                paper: Self.paper(light: (0.990, 0.995, 0.985), dark: (0.215, 0.245, 0.222)),
                paperBack: Self.paper(light: (0.970, 0.980, 0.965), dark: (0.198, 0.226, 0.204)))
        }
    }

    typealias RGB = (red: CGFloat, green: CGFloat, blue: CGFloat)

    /// Quanto o alto contraste afasta fundo e papel um do outro.
    private static let contrastStep: CGFloat = 0.08

    /// Um fundo: com Aumentar Contraste, escurece nos dois modos, para o papel se destacar mais.
    private static func surface(light: RGB, dark: RGB) -> Color {
        dynamic(
            light: nsColor(light), dark: nsColor(dark),
            lightHighContrast: nsColor(light).blended(withFraction: contrastStep, of: .black) ?? nsColor(light),
            darkHighContrast: nsColor(dark).blended(withFraction: contrastStep, of: .black) ?? nsColor(dark))
    }

    /// Um papel: com Aumentar Contraste, clareia no escuro; no claro já está no limite.
    private static func paper(light: RGB, dark: RGB) -> Color {
        dynamic(
            light: nsColor(light), dark: nsColor(dark),
            lightHighContrast: nsColor(light),
            darkHighContrast: nsColor(dark).blended(withFraction: contrastStep, of: .white) ?? nsColor(dark))
    }

    private static func nsColor(_ rgb: RGB) -> NSColor {
        NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }

    private static func dynamic(
        light: NSColor, dark: NSColor, lightHighContrast: NSColor, darkHighContrast: NSColor
    ) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ])
                return switch match {
                case .darkAqua: dark
                case .accessibilityHighContrastAqua: lightHighContrast
                case .accessibilityHighContrastDarkAqua: darkHighContrast
                default: light
                }
            })
    }
}

/// A paleta escolhida pela pessoa, lida das preferências ao criar e gravada a cada mudança. Como `Theme` lê daqui, toda
/// view que usa as cores do tema no `body` passa a depender desta paleta e é redesenhada quando ela muda.
///
/// Nos testes de interface as preferências são as de um conjunto próprio, que não mexe nas do app.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    /// A chave das preferências.
    static let key = "themePalette"

    var palette: ThemePalette {
        didSet {
            guard palette != oldValue else { return }
            preferences.set(palette.rawValue, forKey: Self.key)
        }
    }

    /// As cores da paleta atual.
    var colors: ThemePalette.Colors { palette.colors }

    private let preferences: UserDefaults

    init(preferences: UserDefaults = ThemeStore.defaultPreferences()) {
        self.preferences = preferences
        palette = preferences.string(forKey: Self.key).flatMap(ThemePalette.init(rawValue:)) ?? .neutral
    }

    static func defaultPreferences() -> UserDefaults {
        guard LaunchConfiguration.isUITesting else { return .standard }
        return UserDefaults(suiteName: "com.joaocosta.Mural.uitests") ?? .standard
    }
}

#if DEBUG
#Preview("Paletas") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(ThemePalette.allCases) { palette in
            HStack(spacing: 8) {
                Text(palette.title).frame(width: 60, alignment: .leading)
                ForEach(
                    [
                        palette.colors.canvas, palette.colors.canvasDeep, palette.colors.page, palette.colors.paper,
                        palette.colors.paperBack,
                    ],
                    id: \.self
                ) { color in
                    RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 44, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.quaternary))
                }
            }
        }
    }
    .padding(24)
}
#endif
