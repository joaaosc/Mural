import SwiftUI

/// Barra flutuante do canto superior esquerdo: voltar (quando há para onde) e os filtros.
/// O botão de voltar nasce e some fundindo-se ao grupo de filtros.
struct GlassToolbar: View {
    var canGoBack: Bool
    var onBack: () -> Void
    @Binding var filter: BoardFilter?

    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if canGoBack {
                    Button("Voltar", systemImage: "arrow.left", action: onBack)
                        .labelStyle(.iconOnly)
                        .frame(width: 30, height: 30)
                        .contentShape(.circle)
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("back", in: glass)
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Voltar (⌘[ ou Esc)")
                }

                HStack(spacing: 0) {
                    ForEach(BoardFilter.allCases) { option in
                        Button(option.title, systemImage: option.symbol) {
                            filter = filter == option ? nil : option
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                        .foregroundStyle(filter == option ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                        .help("Destacar \(option.title.lowercased())")
                        .accessibilityAddTraits(filter == option ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 4)
                .glassEffect(.regular.interactive(), in: .capsule)
                .glassEffectID("filters", in: glass)
            }
        }
        .font(.system(size: 13, weight: .medium))
    }
}

#Preview {
    @Previewable @State var filter: BoardFilter? = .notes
    VStack(alignment: .leading, spacing: 20) {
        GlassToolbar(canGoBack: false, onBack: {}, filter: $filter)
        GlassToolbar(canGoBack: true, onBack: {}, filter: $filter)
    }
    .padding(40)
    .background(Theme.canvas)
}
