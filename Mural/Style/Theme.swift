import AppKit
import MuralKit
import SwiftUI

/// Cores e medidas do mural, com variante clara e escura.
enum Theme {
    /// Fundo cinza do mural e das coleções.
    static let canvas = dynamic(
        light: NSColor(srgbRed: 0.895, green: 0.902, blue: 0.914, alpha: 1),
        dark: NSColor(srgbRed: 0.118, green: 0.122, blue: 0.133, alpha: 1))
    /// Fundo claro das telas de detalhe.
    static let page = dynamic(
        light: NSColor(srgbRed: 0.957, green: 0.965, blue: 0.976, alpha: 1),
        dark: NSColor(srgbRed: 0.090, green: 0.094, blue: 0.102, alpha: 1))
    /// Papel dos cartões de texto.
    static let paper = dynamic(
        light: .white,
        dark: NSColor(srgbRed: 0.200, green: 0.204, blue: 0.216, alpha: 1))
    /// Folha de trás da pasta: um tom entre o papel e o mural, mas opaco, para a mídia
    /// guardada atrás dela não aparecer através da folha.
    static let paperBack = dynamic(
        light: NSColor(srgbRed: 0.984, green: 0.985, blue: 0.987, alpha: 1),
        dark: NSColor(srgbRed: 0.188, green: 0.192, blue: 0.204, alpha: 1))

    static let cardCorner: CGFloat = 8
    static let mediaCorner: CGFloat = 12

    /// Quanto da cor da tag cobre o papel do cartão; o cartão continua opaco.
    static let tagWash: Double = 0.18
    /// Quanto da cor da tag cobre a folha de trás da pasta, que é mais clara que a da frente.
    static let tagWashBack: Double = 0.26

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
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            })
    }
}

/// Fundo de cada nível: o mural deixa passar um pouco do material da janela (`MuralApp`), e as
/// páginas de pasta e de item ficam foscas sobre o mural, que aparece só como um borrão de cor.
/// Com Reduzir Transparência, os três ficam sólidos, nas cores de `Theme.canvas` e `Theme.page`.
/// Cartões, post-its e mídia continuam sempre opacos: são conteúdo, não fundo.
enum Surface {
    /// O mural, logo acima do material da janela.
    case board
    /// A página de uma pasta aberta, por cima do mural.
    case collectionPage
    /// A página de um item aberto, por cima do mural ou da pasta.
    case itemPage
}

/// O fundo de um nível (`Surface`), já respeitando Reduzir Transparência.
struct SurfaceFill: View {
    let surface: Surface
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Quanto da cor do mural cobre o material da janela: pouco, para o mural parecer vidro e se distinguir
    /// da barra lateral (mais encorpada); os cartões, opacos e com sombra, continuam se destacando.
    private static let boardTint = 0.3
    /// Quanto da cor da página cobre o material sobre o mural: o mural vira só um tom por trás.
    private static let pageTint = 0.82

    init(_ surface: Surface) {
        self.surface = surface
    }

    var body: some View {
        if reduceTransparency {
            solid
        } else {
            switch surface {
            case .board:
                Theme.canvas.opacity(Self.boardTint)
            case .collectionPage:
                Rectangle().fill(.regularMaterial).overlay(Theme.canvas.opacity(Self.pageTint))
            case .itemPage:
                Rectangle().fill(.regularMaterial).overlay(Theme.page.opacity(Self.pageTint))
            }
        }
    }

    private var solid: Color {
        surface == .itemPage ? Theme.page : Theme.canvas
    }
}

extension View {
    /// Sombra suave dos cartões sobre o mural.
    func cardShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: 6, y: 3)
    }

    /// Folha de papel dos cartões de nota, lista e pasta. Com `tint`, a cor da tag cobre o papel
    /// em `Theme.tagWash`; o fundo continua opaco.
    func paperSheet(tint: Color? = nil) -> some View {
        padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                // `.continuous` é o canto de `.rect(cornerRadius:)`, que o papel usava antes da cor.
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Theme.paper)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                                .fill(tint.opacity(Theme.tagWash))
                        }
                    }
            }
            .cardShadow()
    }
}

extension PaletteColor {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

extension Font {
    /// Texto corrido das notas e legendas.
    static let reading = Font.system(.body, design: .serif)
}
