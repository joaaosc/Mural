import MuralKit
import SwiftUI

/// Um cartão de dentro da pasta, do jeito que aparece espiando pela borda dela.
struct FolderPeekItem: Identifiable, Equatable {
    let id: UUID
    let kind: ItemKind
    let title: String
    /// Arquivo da foto, do vídeo ou do PDF; `nil` para nota, lista e post-it.
    let fileURL: URL?
    let stickyColor: StickyColor?

    /// Os `limit` cartões mais recentes da pasta, do mais antigo ao mais novo: o último fica na frente.
    /// - Parameter children: cartões da pasta na ordem de criação (`BoardModel.children(of:)`).
    static func latest(
        _ children: [BoardItem], limit: Int = 3, fileURL: (BoardItem) -> URL?
    ) -> [FolderPeekItem] {
        children.suffix(max(limit, 0)).map { child in
            FolderPeekItem(
                id: child.id,
                kind: child.kind,
                title: child.title,
                fileURL: child.kind.storesFile ? fileURL(child) : nil,
                stickyColor: child.stickyColor)
        }
    }
}

/// Miniatura de um cartão que espia pela borda da pasta: foto, vídeo e PDF pela imagem; nota e
/// lista como papelzinho com o título; post-it na própria cor.
struct FolderPeekTile: View {
    let item: FolderPeekItem
    let size: CGSize

    var body: some View {
        content
            // O tamanho vale antes do recorte: a foto preenche a miniatura e o que passa dela é cortado.
            .frame(width: size.width, height: size.height)
            // Papel por baixo de tudo: a miniatura é sólida mesmo enquanto a imagem carrega.
            .background(Theme.paper)
            .clipShape(.rect(cornerRadius: Theme.cardCorner))
            .cardShadow()
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .image, .video:
            ThumbnailView(url: item.fileURL, kind: item.kind, maxPixelSize: 240)
        case .pdf:
            ThumbnailView(url: item.fileURL, kind: item.kind, maxPixelSize: 240, contentMode: .fit)
        case .sticky:
            label(ink: Theme.stickyInk, design: .monospaced)
                .background(Theme.sticky(item.stickyColor))
        case .text, .checklist, .folder:
            label(ink: .secondary, design: .default)
        }
    }

    private func label(ink: some ShapeStyle, design: Font.Design) -> some View {
        Text(item.title)
            .font(.system(size: 6, weight: .medium, design: design))
            .foregroundStyle(ink)
            .lineLimit(6)
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
