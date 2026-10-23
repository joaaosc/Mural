import MuralKit
import SwiftUI

/// Texto livre desenhado como uma superfície quadrada independente dos cartões.
struct BoardFreeTextView: View {
    let freeText: BoardFreeText
    var onEdit: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some View {
        Text(freeText.text.isEmpty ? "Texto livre" : freeText.text)
            .font(.system(size: 20, weight: .regular, design: .default))
            .multilineTextAlignment(.center)
            // O conteúdo continua limitado no domínio a 280 caracteres; o limite
            // visual mantém a anotação dentro do quadrado fixo em vez de alterar
            // sua proporção quando o texto é longo.
            .lineLimit(10)
            .minimumScaleFactor(0.65)
            .frame(
                width: BoardLayout.freeTextSide,
                height: BoardLayout.freeTextSide,
                alignment: .center
            )
            .clipped()
            .contentShape(Rectangle())
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(freeText.text.isEmpty ? "Texto livre vazio" : freeText.text)
            .accessibilityHint("Clique duas vezes para editar. Arraste para mover.")
            .onTapGesture(count: 2, perform: onEdit)
            .contextMenu {
                Button("Editar", systemImage: "pencil", action: onEdit)
                if let onDelete {
                    Button("Apagar", systemImage: "trash", role: .destructive, action: onDelete)
                }
            }
    }
}

struct BoardFreeTextEditorView: View {
    let initialText: String
    var onSave: (String) -> Void
    var onCancel: () -> Void

    @State private var text: String

    init(initialText: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.initialText = initialText
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Texto livre")
                .font(.headline)
            TextEditor(text: $text)
                .font(.system(size: 18, weight: .regular, design: .default))
                .frame(minHeight: 150)
                .onChange(of: text) { _, value in
                    let normalized = BoardFreeText.normalized(value)
                    if normalized != value { text = normalized }
                }
            HStack {
                Text("\(text.count)/\(BoardFreeText.maximumCharacters)")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(text.count) de \(BoardFreeText.maximumCharacters) caracteres")
                Spacer()
                Button("Cancelar", role: .cancel, action: onCancel)
                Button("Salvar") { onSave(text) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

struct BoardFreeTextEditorRequest: Identifiable {
    let id: UUID
    let isNew: Bool
}
