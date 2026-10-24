import AppKit
import SwiftUI

/// O que o painel pede ao conteúdo para ter o tamanho certo.
///
/// O vidro não passa o tamanho do conteúdo para a janela; um painel que acompanha o conteúdo, como o da barra de menus,
/// pede a medida de forma explícita.
@MainActor
protocol PanelContentMeasuring: AnyObject {
    /// O tamanho que o conteúdo pede na largura `width`, sem teto de altura.
    func idealSize(forWidth width: CGFloat) -> CGSize
}

/// Medidas do painel flutuante. Um lugar só, para o canto do painel, o recorte do conteúdo e as linhas por dentro
/// nunca se afastarem por um ponto.
enum PanelMetrics {
    /// O canto do painel.
    static let cornerRadius: CGFloat = 18
    /// A margem que o conteúdo mantém da própria borda.
    static let contentPadding: CGFloat = 16
    /// O espaço entre as seções empilhadas.
    static let contentSpacing: CGFloat = 12
    /// O canto de uma linha selecionada: um pouco mais fechado que o do painel, para a seleção parecer uma pílula
    /// dentro da lista.
    static let rowCornerRadius: CGFloat = 10
    /// A largura do painel, fixa: ele não se redimensiona na horizontal.
    static let panelWidth: CGFloat = 600
    /// O piso de altura, que também vale quando o conteúdo não informa tamanho: um painel quase vazio ainda é um painel.
    static let minimumHeight: CGFloat = 120
    /// O teto de altura. Cabe a vitrine com as sete formatações do texto e o rodapé, e fica abaixo da área visível de
    /// uma tela de notebook.
    static let maximumHeight: CGFloat = 680

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius)
    }

    static var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
    }
}

/// Quem desenha o vidro (Liquid Glass) do painel, em AppKit.
///
/// ```
/// NSPanel
///   └── GlassHostingView (NSGlassEffectView: material, refração, cantos)
///         └── contentView: view do NSHostingController (a árvore SwiftUI)
/// ```
///
/// Dois detalhes importam:
///
/// - A árvore SwiftUI é o `contentView` do vidro, que é o lugar que o AppKit documenta como "dentro do efeito"; uma
///   subview ao lado dele não entra. O vidro a mantém do tamanho dele, sem acerto de frame aqui.
/// - `sizingOptions = []`. A árvore SwiftUI não impõe o tamanho dela ao vidro nem à janela: o painel decide o próprio
///   tamanho, sem brigar com o tamanho intrínseco do conteúdo a cada atualização. O preço é que `fittingSize` devolve
///   zero, e por isso o tamanho é pedido por ``idealSize(forWidth:)``.
///
/// O lado SwiftUI nunca desenha material próprio (ver `PanelGlassSurface`): um vidro por painel, e ele é daqui.
final class GlassHostingView<Content: View>: NSGlassEffectView, PanelContentMeasuring {
    private let hostingController: NSHostingController<Content>

    init(rootView: Content, cornerRadius: CGFloat = PanelMetrics.cornerRadius) {
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = []
        hostingController = controller
        super.init(frame: .zero)

        style = .regular
        self.cornerRadius = cornerRadius
        // Sem tinta: o vidro não tem cor própria e toma a do que está atrás dele. A HIG reserva o vidro tingido para
        // uma ação principal, e um painel não é uma.
        tintColor = nil
        contentView = controller.view
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func idealSize(forWidth width: CGFloat) -> CGSize {
        hostingController.sizeThatFits(
            in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
    }
}

/// O que o painel desenha por cima do vidro: nada em repouso, uma placa só quando um ajuste de acessibilidade pede, e
/// uma borda com Aumentar Contraste.
///
/// O material é do `GlassHostingView`. Desenhar outro `.glassEffect` aqui poria vidro sobre vidro, e tingir ou cobrir
/// o vidro tira dele o que ele tem de útil: não ter cor própria e mostrar, desfocado, o que está atrás.
struct PanelGlassSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// A opacidade da placa atrás do conteúdo.
    ///
    /// Em repouso o vidro regular já desfoca e ajusta a luminosidade do que está atrás para manter o texto legível, e
    /// uma placa por cima só o deixaria leitoso. Reduzir Transparência pede superfície opaca; Aumentar Contraste leva a
    /// placa para perto do opaco, porque a refração é enfeite e o texto não é.
    static func plateOpacity(reduceTransparency: Bool, contrast: ColorSchemeContrast) -> Double {
        if reduceTransparency { return 1 }
        return contrast == .increased ? 0.85 : 0
    }

    var body: some View {
        content
            .background {
                // Com Reduzir Transparência a placa é opaca mesmo que o vidro atrás já tenha virado sólido: a garantia
                // não deve depender de como o material se degrada. `ignoresSafeArea` para a placa cobrir o painel
                // inteiro, sem faixa no topo se o hospedeiro reservar uma área segura.
                Color(nsColor: .windowBackgroundColor)
                    .opacity(Self.plateOpacity(reduceTransparency: reduceTransparency, contrast: contrast))
                    .ignoresSafeArea()
            }
            .clipShape(PanelMetrics.shape)
            .overlay {
                // Aumentar Contraste pede bordas visíveis; o brilho do próprio vidro é fraco demais para contar.
                if contrast == .increased {
                    PanelMetrics.shape
                        .strokeBorder(.primary.opacity(0.45), lineWidth: 1)
                        .ignoresSafeArea()
                }
            }
    }
}

extension View {
    /// Põe a vista na camada do painel flutuante. O vidro em si vem do `GlassHostingView` do painel.
    func panelGlassSurface() -> some View {
        PanelGlassSurface { self }
    }
}
