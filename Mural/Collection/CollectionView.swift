import MuralKit
import SwiftUI

/// Nível 2: o conteúdo de uma pasta. Mídia numa faixa à esquerda, notas e listas
/// numa faixa mais estreita à direita, só com as colunas que os itens ocupam.
struct CollectionView: View {
    let folder: BoardItem
    let model: BoardModel
    let hero: HeroContext
    let filter: BoardFilter?
    var onOpenItem: (UUID) -> Void

    private var children: [BoardItem] { model.children(of: folder.id) }

    var body: some View {
        ScrollView {
            Group {
                if children.isEmpty {
                    emptyState
                } else {
                    GalleryLayout {
                        ForEach(children) { item in
                            card(for: item)
                                .galleryLane(item.kind.storesFile ? .media : .notes)
                        }
                    }
                }
            }
            .padding(.leading, 104)
            .padding(.trailing, 64)
            .padding(.top, 70)
            .padding(.bottom, 90)
        }
        .scrollIndicators(.automatic)
        .overlay(alignment: .topTrailing) {
            FolderInfoButton(folder: folder, children: children)
                .padding(12)
                .containerCornerOffset(.top)
        }
    }

    private func card(for item: BoardItem) -> some View {
        HeroSlot(id: item.id, context: hero) {
            Button {
                onOpenItem(item.id)
            } label: {
                CardView(item: item, model: model)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.title)
            .contextMenu {
                Button("Abrir") { onOpenItem(item.id) }
                Divider()
                Button("Apagar", role: .destructive) { model.delete(item.id) }
            }
        }
        .aspectRatio(CardView.aspectRatio(for: item), contentMode: .fit)
        .opacity(filter.map { $0.matches(item.kind) ? 1 : 0.25 } ?? 1)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Pasta vazia", systemImage: "rectangle.stack")
        } description: {
            Text("Copie imagens, vídeos, PDFs ou texto e cole aqui com ⌘V, ou arraste para a janela.")
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}
