import MuralKit
import SwiftUI

/// Um cartão de dentro da pasta, do jeito que aparece espiando pela borda dela.
struct FolderPeekItem: Identifiable, Equatable {
    let id: UUID
    let kind: ItemKind
    let title: String
    /// Arquivo da foto, do vídeo ou do PDF, ou a imagem de prévia de um link; `nil` para nota, lista e post-it.
    let fileURL: URL?
    let stickyColor: StickyColor?

    /// Os `limit` cartões mais recentes da pasta, do mais antigo ao mais novo: o último fica na frente.
    /// - Parameters:
    ///   - children: cartões da pasta na ordem de criação (`BoardModel.children(of:)`).
    ///   - linkPreviewURL: a imagem de prévia de um link, se ela estiver guardada.
    static func latest(
        _ children: [BoardItem], limit: Int = 3, fileURL: (BoardItem) -> URL?,
        linkPreviewURL: (BoardItem) -> URL? = { _ in nil }
    ) -> [FolderPeekItem] {
        children.suffix(max(limit, 0)).map { child in
            let url: URL? =
                if child.kind == .link { linkPreviewURL(child) } else { child.kind.storesFile ? fileURL(child) : nil }
            return FolderPeekItem(
                id: child.id,
                kind: child.kind,
                title: child.title,
                fileURL: url,
                stickyColor: child.stickyColor)
        }
    }
}

extension FolderPeekItem {
    /// A imagem de prévia de um link, só se o arquivo estiver na pasta de prévias. Arquivo que sumiu (mural
    /// promovido ou importado sem as prévias) não espia: o link aparece pelo título.
    static func linkPreviewURL(of item: BoardItem, in files: LinkPreviewFiles?) -> URL? {
        guard let name = item.link?.previewImageFile else { return nil }
        return files?.existingURL(for: name)
    }
}

/// Miniatura de um cartão que espia pela borda da pasta: foto, vídeo e PDF pela imagem; link pela imagem
/// de prévia; nota, lista e link sem imagem como papelzinho com o título; post-it na própria cor.
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
        case .link where item.fileURL != nil:
            ThumbnailView(url: item.fileURL, kind: .image, maxPixelSize: 240)
        case .text, .checklist, .folder, .link:
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
