import MuralKit
import SwiftUI

/// Popup do ⌘V com texto solto: mostra o começo do texto e pergunta se ele vira
/// sticker, card de texto ou (quando o texto parece lista) lista. A sugestão vem
/// marcada: Return confirma, Esc cancela sem criar nada.
struct PasteChoiceSheet: View {
    let paste: PendingPaste
    var onChoose: (ItemKind) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Colar texto como")
                .font(.title3.weight(.semibold))
            Text(verbatim: paste.preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
                .accessibilityLabel("Texto colado")
                .accessibilityValue(paste.preview)
            HStack(spacing: 8) {
                Button("Cancelar", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                ForEach(paste.choice.options, id: \.self) { kind in
                    PasteChoiceButton(kind: kind, isSuggested: kind == paste.choice.suggested) {
                        onChoose(kind)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

#Preview("Texto curto") {
    PasteChoiceSheet(paste: PendingPaste(text: "Ligar para o marceneiro", folderID: nil), onChoose: { _ in }, onCancel: {})
}

#Preview("Parece lista") {
    PasteChoiceSheet(
        paste: PendingPaste(text: "Compras da obra\n- [ ] Tinta azul\n- [ ] Rolo\n- [x] Fita crepe", folderID: nil),
        onChoose: { _ in }, onCancel: {})
}
