import SwiftUI

/// Pílula flutuante do detalhe de um link: página anterior e próxima, recarregar, abrir no navegador, copiar,
/// usar como prévia e apagar.
///
/// Tem o mesmo desenho de `ActionPill`, mas cada botão pode ficar desligado (não há para onde voltar, por exemplo).
struct LinkActionPill: View {
    /// Uma ação da pílula.
    struct Action: Identifiable {
        let title: String
        let symbol: String
        var role: ButtonRole?
        var isEnabled = true
        let perform: () -> Void

        var id: String { title }
    }

    let actions: [Action]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                Button(role: action.role, action: action.perform) {
                    Label(action.title, systemImage: action.symbol)
                        .labelStyle(.iconOnly)
                        .frame(width: 34, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(action.role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                .opacity(action.isEnabled ? 1 : 0.35)
                .disabled(!action.isEnabled)
                .help(action.title)
            }
        }
        .font(.body.weight(.medium))
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .capsule)
    }
}
