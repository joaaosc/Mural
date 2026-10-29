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
    var onNewFreeText: (() -> Void)? = nil
    /// `nil` quando não dá para criar pasta ali (por exemplo, no último nível de pastas).
    var onNewFolder: (() -> Void)? = nil
    var onAddFiles: () -> Void
    var onAddPhotos: () -> Void = {}
    var onAddReminders: () -> Void = {}

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 2) {
                actionButtons
            }
            .labelStyle(.titleAndIcon)

            HStack(spacing: 2) {
                actionButtons
            }
            .labelStyle(.iconOnly)

            Menu {
                actionButtons
            } label: {
                Label("Criar", systemImage: "plus")
            }
            .help("Criar ou adicionar conteúdo ao mural")
        }
        .buttonStyle(CreationBarButtonStyle())
        .padding(4)
        .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button(ItemKind.text.creationTitle, systemImage: ItemKind.text.creationSymbol, action: onNewNote)
            .help("Novo card de texto (⇧⌘N)")
        Button(ItemKind.sticky.creationTitle, systemImage: ItemKind.sticky.creationSymbol, action: onNewSticky)
            .help("Novo sticker (⌥⌘N)")
        if let onNewFreeText {
            Button("Texto livre", systemImage: "text.aligncenter", action: onNewFreeText)
                .help("Novo texto livre")
        }
        if let onNewFolder {
            Button(ItemKind.folder.creationTitle, systemImage: ItemKind.folder.creationSymbol, action: onNewFolder)
                .help("Nova pasta (⌃⌘N)")
        }
        Button("Arquivos…", systemImage: "paperclip", action: onAddFiles)
            .help("Adicionar arquivos (⇧⌘I) — ou cole com ⌘V")
        Button("Fotos…", systemImage: "photo.on.rectangle", action: onAddPhotos)
            .accessibilityLabel("Adicionar fotos e vídeos do app Fotos")
            .accessibilityIdentifier("photos-import-button")
            .help("Adicionar fotos e vídeos do app Fotos")
        Button("Lembretes…", systemImage: "checklist.checked", action: onAddReminders)
            .help("Adicionar lembretes do app Lembretes")
    }
}

#Preview {
    CreationBar(onNewNote: {}, onNewSticky: {}, onNewFolder: {}, onAddFiles: {})
        .padding(40)
        .background { PreviewBackdrop() }
}
