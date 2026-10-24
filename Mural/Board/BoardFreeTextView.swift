import MuralKit
import SwiftUI

/// Texto livre desenhado como uma superfície independente dos cartões: um quadrado de 180 pontos ou o tamanho que a pessoa
/// escolheu.
struct BoardFreeTextView: View {
    let freeText: BoardFreeText
    /// Tamanho mostrado agora, em pontos do mural: o do texto ou, durante o arrasto do canto, o que o arrasto dá a ele.
    let size: BoardSize
    var onEdit: () -> Void
    var onDelete: (() -> Void)? = nil
    /// Muda o tamanho pelo menu; `nil` esconde a ação. Recebe `nil` para voltar ao quadrado padrão.
    var onResize: ((BoardSize?) -> Void)? = nil

    /// Letra do texto no quadrado padrão.
    private static let standardFontSize: CGFloat = 20

    /// Tamanho da letra de um texto livre mostrado em `size`: 20 pontos no quadrado padrão e, a partir daí, proporcional ao tamanho
    /// (`BoardLayout.contentScale`). A capa usa a mesma conta para desenhar o texto como o mural.
    static func fontSize(for size: BoardSize) -> CGFloat {
        standardFontSize
            * BoardLayout.contentScale(
                width: size.width, height: size.height,
                defaultWidth: BoardLayout.freeTextSide, defaultHeight: BoardLayout.freeTextSide)
    }

    var body: some View {
        Text(freeText.text.isEmpty ? "Texto livre" : freeText.text)
            .font(.system(size: Self.fontSize(for: size), weight: .regular, design: .default))
            .multilineTextAlignment(.center)
            // O conteúdo continua limitado no domínio a 280 caracteres; o limite
            // visual mantém a anotação dentro da caixa em vez de alterar
            // sua proporção quando o texto é longo.
            .lineLimit(10)
            .minimumScaleFactor(0.65)
            .frame(
                width: size.width,
                height: size.height,
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
                if let onResize {
                    BoardSizeMenu(
                        sides: BoardLayout.freeTextPresetSides,
                        isStandard: size.width == BoardLayout.freeTextSize.width && size.height == BoardLayout.freeTextSize.height,
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        onSelect: onResize)
                }
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
