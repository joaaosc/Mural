import MuralKit
import SwiftUI

/// Barra do seletor, no lugar da barra de criação enquanto a seleção está aberta: quantos
/// cartões estão marcados, Cor, Apagar… e Cancelar. Mesmo vidro e botões da barra de criação.
struct SelectionBar: View {
    let count: Int
    /// Dá a cor (ou tira, com `nil`) aos cartões marcados.
    var onColor: (TagColor?) -> Void = { _ in }
    var onDelete: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.body.weight(.medium))
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.horizontal, 12)
            colorButtons
            Button("Apagar…", systemImage: "trash", role: .destructive, action: onDelete)
                .foregroundStyle(count == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.red))
                .disabled(count == 0)
                .help("Apagar os cartões marcados (⌫)")
            Button("Cancelar", systemImage: "xmark", action: onCancel)
                .help("Desmarcar tudo (Esc)")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(CreationBarButtonStyle())
        .padding(4)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection-bar")
    }

    /// As mesmas sete cores do menu do cartão, direto na barra: um clique pinta todos os marcados, e o
    /// último botão tira a cor.
    private var colorButtons: some View {
        HStack(spacing: 4) {
            ForEach(TagColor.allCases) { color in
                Button {
                    onColor(color)
                } label: {
                    Circle()
                        .fill(color.color)
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(color.displayName)
            }
            Button {
                onColor(nil)
            } label: {
                Image(systemName: "circle.slash")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .help("Remover cor")
            .accessibilityLabel("Remover cor")
        }
        .padding(.horizontal, 6)
        .opacity(count == 0 ? 0.4 : 1)
        .disabled(count == 0)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cor dos marcados")
        .accessibilityIdentifier("selection-color")
    }

    private var title: String {
        switch count {
        case 0: "Clique nos cartões para marcar"
        case 1: "1 selecionado"
        default: "\(count) selecionados"
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SelectionBar(count: 0, onDelete: {}, onCancel: {})
        SelectionBar(count: 3, onDelete: {}, onCancel: {})
    }
    .padding(40)
    .background { PreviewBackdrop() }
}
