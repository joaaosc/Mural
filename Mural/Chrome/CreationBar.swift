import MuralKit
import SwiftUI

/// Barra de criação no centro inferior: card de texto, sticker, pasta e arquivos, as
/// formas de pôr conteúdo no mural (ou na pasta aberta) sem colar.
///
/// Mesmo desenho do grupo de filtros da barra superior: um vidro estático por
/// trás de botões sem borda, com ícone e nome.
struct CreationBar: View {
    var onNewNote: () -> Void
    var onNewSticky: () -> Void
    /// `nil` quando não dá para criar pasta ali (por exemplo, no último nível de pastas).
    var onNewFolder: (() -> Void)? = nil
    var onAddFiles: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button(ItemKind.text.creationTitle, systemImage: ItemKind.text.creationSymbol, action: onNewNote)
                .help("Novo card de texto (⇧⌘N)")
            Button(ItemKind.sticky.creationTitle, systemImage: ItemKind.sticky.creationSymbol, action: onNewSticky)
                .help("Novo sticker (⌥⌘N)")
            if let onNewFolder {
                Button(ItemKind.folder.creationTitle, systemImage: ItemKind.folder.creationSymbol, action: onNewFolder)
                    .help("Nova pasta (⌃⌘N)")
            }
            Button("Arquivos…", systemImage: "paperclip", action: onAddFiles)
                .help("Adicionar arquivos (⇧⌘I) — ou cole com ⌘V")
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(CreationBarButtonStyle())
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }
}

#Preview {
    CreationBar(onNewNote: {}, onNewSticky: {}, onNewFolder: {}, onAddFiles: {})
        .padding(40)
        .background { PreviewBackdrop() }
}
