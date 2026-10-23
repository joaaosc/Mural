import SwiftUI

/// O preenchimento sob a linha em que o usuário está: uma pílula neutra e translúcida na cor do rótulo, não um
/// bloco de destaque.
///
/// É assim que a Siri, o Spotlight e as barras laterais do sistema marcam onde você está sobre vidro: a linha sobe
/// um pouco e o texto mantém a própria cor. A HIG gasta cor com uma ação principal ou um estado; a seleção de uma
/// lista não é nenhum dos dois, e um bloco de destaque sob texto branco ainda amarra a legibilidade à cor de destaque
/// que a pessoa escolheu. A seleção inativa é ainda mais fraca, para uma linha em que ninguém pode agir agora não
/// competir com uma em que pode.
enum PanelSelection {
    static var fill: Color { Color.primary.opacity(Metrics.activeOpacity) }
    static var inactiveFill: Color { Color.primary.opacity(Metrics.inactiveOpacity) }

    fileprivate enum Metrics {
        static let activeOpacity: Double = 0.10
        static let inactiveOpacity: Double = 0.05
        static let contrastOpacity: Double = 0.16
        static let contrastEdgeOpacity: Double = 0.45
    }
}

struct PanelSelectionBackground: View {
    /// Compartilhado por todas as linhas da mesma lista, para a pílula ser uma só identidade deslizando entre as
    /// linhas, e não uma nova surgindo a cada troca. `nil` para quem não precisa animar.
    var namespace: Namespace.ID?
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.colorSchemeContrast) private var contrast

    /// O id que a pílula de toda linha compartilha dentro de `namespace`. Uma linha é selecionada por vez, e um id só
    /// faz o SwiftUI ler a troca como deslize, e não como remoção seguida de inserção.
    static let geometryID = "panel-selection-pill"

    var body: some View {
        let shape = PanelMetrics.rowShape
        Group {
            if !appearsActive {
                shape.fill(PanelSelection.inactiveFill)
            } else if contrast == .increased {
                // Aumentar Contraste pede uma marca com borda, não uma névoa.
                shape
                    .fill(Color.primary.opacity(PanelSelection.Metrics.contrastOpacity))
                    .overlay {
                        shape.strokeBorder(
                            Color.primary.opacity(PanelSelection.Metrics.contrastEdgeOpacity),
                            lineWidth: 1
                        )
                    }
            } else {
                shape.fill(PanelSelection.fill)
            }
        }
        .modifier(OptionalMatchedGeometry(namespace: namespace))
    }
}

/// Aplica `matchedGeometryEffect` quando há um namespace e deixa a vista como está quando não há. Separado para o
/// fundo da seleção não repetir três ramos de `Group`, um por preenchimento, cada um com a mesma condicional.
private struct OptionalMatchedGeometry: ViewModifier {
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedGeometryEffect(id: PanelSelectionBackground.geometryID, in: namespace)
        } else {
            content
        }
    }
}

/// Põe a linha na seleção do painel. A pílula é neutra, então o texto e os símbolos da linha mantêm as cores de
/// rótulo deles sobre ela.
struct PanelRowHighlight: ViewModifier {
    let isSelected: Bool
    /// Passado por uma lista que cuida das próprias linhas, para a pílula deslizar entre elas; `nil` para as linhas de
    /// uma `List`, que já animam a própria seleção.
    var namespace: Namespace.ID?

    func body(content: Content) -> some View {
        content
            .background {
                if isSelected {
                    PanelSelectionBackground(namespace: namespace)
                }
            }
    }
}

extension View {
    /// Desenha a linha como selecionada (ou não) no estilo de seleção do painel.
    func panelRowHighlight(isSelected: Bool, namespace: Namespace.ID? = nil) -> some View {
        modifier(PanelRowHighlight(isSelected: isSelected, namespace: namespace))
    }
}

/// Uma dica de teclado: a tecla e o que ela faz.
///
/// A tecla sozinha não era legível para ninguém: uma fileira de glifos sem rótulo num canto é enfeite, não dica, e só
/// o VoiceOver sabia o significado. `label` é a palavra curta mostrada ao lado da tecla; `description` é a frase
/// inteira que o VoiceOver lê.
struct KeyHint: View {
    let symbol: String
    let label: String
    let description: String
    var isCompact = false

    init(symbol: String, label: String, description: String? = nil, isCompact: Bool = false) {
        self.symbol = symbol
        self.label = label
        self.description = description ?? label
        self.isCompact = isCompact
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .frame(width: 18, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
                )

            if !isCompact {
                Text(label)
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
    }
}

/// O símbolo de uma linha, na cor secundária de rótulo do sistema.
///
/// Monocromático de propósito. A HIG pede cor aplicada com parcimônia e com significado; um quadrado colorido atrás de
/// cada linha vira um muro de destaques disputando atenção. A cor das listas vem de ícones reais, onde houver, e da
/// única ação principal da tela.
struct PanelIconTile: View {
    let symbolName: String
    let size: CGFloat

    init(symbolName: String, size: CGFloat = 26) {
        self.symbolName = symbolName
        self.size = size
    }

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: size * Metrics.symbolFraction))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private enum Metrics {
        /// O tamanho do símbolo como fração do quadro em que ele está, para a linha manter o alinhamento seja qual for
        /// o tamanho pedido.
        static let symbolFraction: CGFloat = 0.62
    }
}

/// A linguagem de movimento do painel: molas, e não `easeInOut`, com uma predefinição nomeada para cada tipo de
/// mudança, para a pílula de seleção e uma linha sob o ponteiro se moverem com o mesmo caráter.
///
/// Reduzir Movimento é respeitado num lugar só, em ``animation(_:reduceMotion:)``, por onde toda vista animada do painel
/// deve passar, em vez de cada uso reconsultar o ambiente.
enum PanelMotion {
    /// A seleção de uma linha deslizando para onde o usuário acabou de ir.
    static let selection: Animation = .snappy(duration: 0.2)
    /// A primeira aparição de uma superfície: escala de 0,98 a 1 mais um fade.
    static let appearance: Animation = .smooth(duration: 0.28)
    /// Uma linha sob o ponteiro se acomodando.
    static let hover: Animation = .snappy(duration: 0.18)

    /// `animation`, ou `nil` quando Reduzir Movimento está ligado.
    ///
    /// O `.animation(_:value:)` do SwiftUI pula a transição inteira quando recebe `nil`: o estado muda do mesmo jeito,
    /// só que na hora, que é o que Reduzir Movimento pede sem o chamador precisar de um `if`.
    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Uma linha selecionável do painel: símbolo, título e um resumo de uma linha, que executa ou abre algo ao ser
/// pressionada.
///
/// Fica num lugar só para uma mudança no formato, no espaçamento ou na seleção da linha chegar a todos os usos de uma
/// vez.
struct PanelActionRow: View {
    let symbolName: String
    let title: String
    let summary: String
    let isSelected: Bool
    /// Compartilhado com as outras linhas selecionáveis da mesma lista, para a pílula deslizar entre elas em vez de
    /// surgir de novo. `nil` para quem não tem uma lista assim.
    var namespace: Namespace.ID? = nil
    /// O que a dica de ferramenta e o rótulo e a dica de acessibilidade da linha dizem que pressionar faz.
    let help: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                PanelIconTile(symbolName: symbolName, size: 22)

                Text(title)
                    .font(.body)
                    .lineLimit(1)

                Spacer(minLength: 12)

                // Só na linha que está sendo lida: o mesmo resumo em toda linha é ruído, não informação.
                if isSelected {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelRowHighlight(isSelected: isSelected, namespace: namespace)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
