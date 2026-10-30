import MuralKit
import SwiftUI

/// A barra de ferramentas do editor de texto: negrito e itálico à esquerda; no centro as quatro formatações com atalho, o lembrete
/// e, num menu, as outras formatações; à direita a contagem de palavras e "Colar no mural…". Todo item também é um comando de
/// menu (`MuralCommands`), e é o menu que guarda o ⌘↩.
struct TextEditorToolbar: ToolbarContent {
    let actions: TextEditorActions
    let wordCount: Int

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Negrito", systemImage: "bold") { actions.applyEmphasis(.bold) }
                .help("Negrito (⌘B)")
                .accessibilityIdentifier("text-editor-bold")
            Button("Itálico", systemImage: "italic") { actions.applyEmphasis(.italic) }
                .help("Itálico (⌘I)")
                .accessibilityIdentifier("text-editor-italic")
        }
        ToolbarItemGroup(placement: .principal) {
            ForEach(TextEditorWording.toolbarFormats) { format in
                Button(format.title, systemImage: format.symbolName) { actions.applyFormat(format) }
                    .help(format.title)
                    .accessibilityIdentifier("text-editor-format-\(format.rawValue)")
            }
            Button("Lembrete", systemImage: "checklist.checked", action: actions.insertReminder)
                .help("Inserir um lembrete do app Lembretes")
                .accessibilityIdentifier("text-editor-reminder")
            Menu("Mais formatações", systemImage: "ellipsis.circle") {
                ForEach(TextEditorWording.menuFormats) { format in
                    Button(format.title, systemImage: format.symbolName) { actions.applyFormat(format) }
                        .help(format.title)
                        .accessibilityIdentifier("text-editor-format-\(format.rawValue)")
                }
            }
            .help("Mais formatações")
            .accessibilityIdentifier("text-editor-more-formats")
        }
        ToolbarItem(placement: .primaryAction) {
            Text(TextEditorWording.wordCount(wordCount))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .accessibilityIdentifier("text-editor-word-count")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            Button("Colar no mural…", systemImage: "arrow.down.doc", action: actions.requestPaste)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .disabled(!actions.canPaste)
                .help("Colar o texto num mural (⌘↩)")
                .accessibilityIdentifier("text-editor-paste")
        }
    }
}
