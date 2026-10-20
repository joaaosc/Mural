import AppKit
import MuralKit
import SwiftUI

/// Cores e medidas do mural, com variante clara e escura.
enum Theme {
    /// Fundo cinza do mural e das coleções.
    static let canvas = dynamic(light: NSColor(srgbRed: 0.895, green: 0.902, blue: 0.914, alpha: 1),
                                dark: NSColor(srgbRed: 0.118, green: 0.122, blue: 0.133, alpha: 1))
    /// Fundo claro das telas de detalhe.
    static let page = dynamic(light: NSColor(srgbRed: 0.957, green: 0.965, blue: 0.976, alpha: 1),
                              dark: NSColor(srgbRed: 0.090, green: 0.094, blue: 0.102, alpha: 1))
    /// Papel dos cartões de texto.
    static let paper = dynamic(light: .white,
                               dark: NSColor(srgbRed: 0.200, green: 0.204, blue: 0.216, alpha: 1))

    static let cardCorner: CGFloat = 8
    static let mediaCorner: CGFloat = 12

    /// Post-its mantêm o tom pastel nos dois modos, como papel de verdade.
    static func sticky(_ color: StickyColor?) -> Color {
        switch color ?? .yellow {
        case .yellow: Color(red: 1.00, green: 0.93, blue: 0.62)
        case .pink: Color(red: 0.99, green: 0.84, blue: 0.88)
        case .orange: Color(red: 0.98, green: 0.45, blue: 0.33)
        case .blue: Color(red: 0.82, green: 0.90, blue: 0.99)
        case .green: Color(red: 0.83, green: 0.94, blue: 0.80)
        }
    }

    /// Texto escuro sobre post-it, legível em qualquer modo.
    static let stickyInk = Color.black.opacity(0.78)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

extension View {
    /// Sombra suave dos cartões sobre o mural.
    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 6, y: 3)
    }
}

extension PaletteColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

extension Font {
    /// Rótulos pequenos em caixa alta, como "CLIENT 001" e os metadados.
    static let label = Font.system(.caption2, design: .monospaced)
    /// Texto corrido das notas e legendas.
    static let reading = Font.system(.body, design: .serif)
}
