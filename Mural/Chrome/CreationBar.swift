import SwiftUI

/// Barra de criação no centro inferior: card de texto, sticker e arquivos, as
/// três formas de pôr conteúdo no mural (ou na pasta aberta) sem colar.
///
/// Mesmo desenho do grupo de filtros da barra superior: um vidro estático por
/// trás de botões sem borda, com ícone e nome.
struct CreationBar: View {
    var onNewNote: () -> Void
    var onNewSticky: () -> Void
    var onAddFiles: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button("Card de texto", systemImage: "text.document", action: onNewNote)
                .help("Novo card de texto (⇧⌘N)")
            Button("Sticker", systemImage: "square.text.square", action: onNewSticky)
                .help("Novo sticker (⌥⌘N)")
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
    CreationBar(onNewNote: {}, onNewSticky: {}, onAddFiles: {})
        .padding(40)
        .background(Theme.canvas)
}
