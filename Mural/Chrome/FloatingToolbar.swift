import MuralKit
import SwiftUI

/// Barra flutuante de navegação e filtros.
///
/// No mural, fica na horizontal só com ícones. Dentro de uma pasta ou de um item, vira
/// uma coluna à esquerda com legenda embaixo de cada ícone; o vidro se transforma de um
/// formato no outro e o botão Voltar nasce do mesmo vidro.
///
/// Voltar e o grupo de filtros são vidro estático por trás de botões sem borda, com a área de clique dentro do rótulo, para o
/// clique valer em todo o espaço visível. Nada aqui usa vidro interativo, nem o `.buttonStyle(.glass)`: nesta barra, que morfa
/// dentro de um `GlassEffectContainer`, ele deixava cliques sem resposta, com o vidro acendendo normalmente.
///
/// O primeiro clique vale mesmo com a janela sem foco (`allowsWindowActivationEvents`): quem volta de outra janela e clica em
/// Voltar não precisa clicar duas vezes.
struct FloatingToolbar: View {
    var level: NavigationLevel
    var onBack: () -> Void
    @Binding var filter: BoardFilter?
    @Binding var colorFilter: TagColor?

    @Namespace private var glass
    @State private var isHoveringBack = false

    private var isRail: Bool { level != .board }
    private var filters: [BoardFilter] { BoardFilter.available(at: level) }

    var body: some View {
        let layout = isRail ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        GlassEffectContainer(spacing: 10) {
            layout {
                if level != .board {
                    backButton
                        .glassEffect(.regular, in: .rect(cornerRadius: 14))
                        .glassEffectID("back", in: glass)
                }
                if !filters.isEmpty {
                    filterGroup
                        .glassEffect(.regular, in: .rect(cornerRadius: isRail ? 16 : 20))
                        .glassEffectID("filters", in: glass)
                }
            }
        }
        .allowsWindowActivationEvents()
    }

    /// As margens ficam dentro do rótulo: são parte da área de clique, e o botão inteiro responde, de borda a borda do vidro.
    private var backButton: some View {
        Button(action: onBack) {
            Label("Voltar", systemImage: "chevron.backward")
                .labelStyle(ToolbarLabelStyle(showsTitle: isRail))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHoveringBack ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 14))
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .onHover { isHoveringBack = $0 }
        .accessibilityLabel("Voltar")
        .keyboardShortcut("[", modifiers: .command)
        .help("Voltar (⌘[ ou Esc)")
    }

    private var filterGroup: some View {
        let layout = isRail ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            ForEach(filters) { option in
                let isSelected = filter == option
                Button(option.title, systemImage: option.symbol) {
                    filter = isSelected ? nil : option
                }
                .labelStyle(ToolbarLabelStyle(showsTitle: isRail))
                .buttonStyle(.borderless)
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .background(isSelected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10))
                .help(isSelected ? "Mostrar tudo" : "Destacar \(option.title.lowercased())")
                // Sem legenda (barra horizontal), o nome precisa vir explícito para a acessibilidade.
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            colorFilterMenu
        }
        // Na coluna, a mesma largura do botão Voltar (rótulo de 56 + margem do vidro).
        .padding(.horizontal, isRail ? 8 : 4)
        .padding(.vertical, 4)
    }
}

extension FloatingToolbar {
    /// Destaque por cor: as sete cores do menu dos cartões; a escolhida esmaece os cartões de outra cor.
    fileprivate var colorFilterMenu: some View {
        Menu {
            Picker("Destacar a cor", selection: $colorFilter) {
                ForEach(TagColor.allCases) { color in
                    Label(color.displayName, systemImage: "circle.fill")
                        .tint(color.color)
                        .tag(Optional(color))
                }
            }
            .pickerStyle(.palette)
            if colorFilter != nil {
                Button("Mostrar todas as cores") { colorFilter = nil }
            }
        } label: {
            Label("Cor", systemImage: colorFilter == nil ? "circle.dashed" : "circle.fill")
                .labelStyle(ToolbarLabelStyle(showsTitle: isRail))
                .foregroundStyle(colorFilter.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.primary))
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .background(
            colorFilter != nil ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10)
        )
        .help(colorFilter.map { "Destacando \($0.displayName.lowercased()) (clique para trocar)" } ?? "Destacar uma cor")
        .accessibilityLabel("Destacar a cor")
        .accessibilityValue(colorFilter?.displayName ?? "Todas")
        .accessibilityIdentifier("color-filter")
    }
}

#Preview("Mural, pasta e item", traits: .fixedLayout(width: 360, height: 360)) {
    @Previewable @State var filter: BoardFilter? = .notes
    @Previewable @State var colorFilter: TagColor? = .green
    HStack(alignment: .top, spacing: 30) {
        FloatingToolbar(level: .board, onBack: {}, filter: $filter, colorFilter: $colorFilter)
        FloatingToolbar(level: .folder, onBack: {}, filter: $filter, colorFilter: $colorFilter)
        FloatingToolbar(level: .item, onBack: {}, filter: $filter, colorFilter: $colorFilter)
    }
    .padding(30)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background { PreviewBackdrop() }
}
