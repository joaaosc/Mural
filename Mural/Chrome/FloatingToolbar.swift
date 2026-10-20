import SwiftUI

/// Barra flutuante de navegação e filtros.
///
/// No mural, fica na horizontal só com ícones. Dentro de uma pasta ou de um item, vira
/// uma coluna à esquerda com legenda embaixo de cada ícone; o vidro se transforma de um
/// formato no outro e o botão Voltar nasce do mesmo vidro.
///
/// Os botões usam o estilo de vidro do sistema (`.glass`); o grupo de filtros é um vidro
/// estático por trás de botões sem borda. Não há vidro interativo aplicado à mão sobre
/// botões: essa combinação deixava cliques sem resposta.
struct FloatingToolbar: View {
    var level: NavigationLevel
    var onBack: () -> Void
    @Binding var filter: BoardFilter?

    @Namespace private var glass

    private var isRail: Bool { level != .board }
    private var filters: [BoardFilter] { BoardFilter.available(at: level) }

    var body: some View {
        let layout = isRail ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        GlassEffectContainer(spacing: 10) {
            layout {
                if level != .board {
                    Button("Voltar", systemImage: "chevron.backward", action: onBack)
                        .labelStyle(ToolbarLabelStyle(showsTitle: isRail))
                        .buttonStyle(.glass)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .glassEffectID("back", in: glass)
                        .accessibilityLabel("Voltar")
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Voltar (⌘[ ou Esc)")
                }
                if !filters.isEmpty {
                    filterGroup
                        .glassEffect(.regular, in: .rect(cornerRadius: isRail ? 16 : 20))
                        .glassEffectID("filters", in: glass)
                }
            }
        }
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
        }
        // Na coluna, a mesma largura do botão Voltar (rótulo de 56 + margem do vidro).
        .padding(.horizontal, isRail ? 8 : 4)
        .padding(.vertical, 4)
    }
}

#Preview("Mural, pasta e item", traits: .fixedLayout(width: 360, height: 360)) {
    @Previewable @State var filter: BoardFilter? = .notes
    HStack(alignment: .top, spacing: 30) {
        FloatingToolbar(level: .board, onBack: {}, filter: $filter)
        FloatingToolbar(level: .folder, onBack: {}, filter: $filter)
        FloatingToolbar(level: .item, onBack: {}, filter: $filter)
    }
    .padding(30)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Theme.canvas)
}
