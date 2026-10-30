import MuralKit
import SwiftUI

/// A barra de ferramentas do editor de texto: negrito e itálico à esquerda; no centro as quatro formatações com atalho e, em menus, o
/// que se pode inserir e as outras formatações; à direita "Colar no mural…". Todo item também é um comando de menu (`MuralCommands`),
/// e é o menu que guarda o ⌘↩.
struct TextEditorToolbar: ToolbarContent {
    let actions: TextEditorActions

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
            Menu("Inserir", systemImage: "plus") {
                ForEach(TextEditorInsertion.allCases) { insertion in
                    if insertion == .finder { Divider() }
                    Button(insertion.title, systemImage: insertion.symbolName) { actions.insert(insertion) }
                        .labelStyle(.titleAndIcon)
                        .accessibilityIdentifier("text-editor-insert-\(insertion.rawValue)")
                }
            }
            .help("Inserir fotos, músicas, lembretes, links e contatos")
            .accessibilityIdentifier("text-editor-insert")
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
            Button("Colar no mural…", systemImage: "arrow.down.doc", action: actions.requestPaste)
                .labelStyle(.titleAndIcon)
                .buttonStyle(.borderedProminent)
                .disabled(!actions.canPaste)
                .help("Colar o texto num mural (⌘↩)")
                .accessibilityIdentifier("text-editor-paste")
        }
    }
}
