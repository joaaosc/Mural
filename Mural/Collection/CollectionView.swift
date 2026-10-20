import MuralKit
import SwiftUI

/// Nível 2: o conteúdo de uma pasta. Mídia numa grade larga à esquerda,
/// notas e listas numa grade mais estreita à direita, com etiquetas nos cantos.
struct CollectionView: View {
    let folder: BoardItem
    let model: BoardModel
    let hero: HeroContext
    let filter: BoardFilter?
    var onOpenItem: (UUID) -> Void

    private var children: [BoardItem] { model.children(of: folder.id) }
    private var media: [BoardItem] { children.filter { $0.kind.storesFile } }
    private var notes: [BoardItem] { children.filter { !$0.kind.storesFile } }

    var body: some View {
        ScrollView {
            Group {
                if children.isEmpty {
                    emptyState
                } else if media.isEmpty || notes.isEmpty {
                    grid(children, columns: 4)
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        grid(media, columns: 3)
                            .containerRelativeFrame(.horizontal) { width, _ in (width - 150) * 0.62 }
                        grid(notes, columns: 2)
                            .containerRelativeFrame(.horizontal) { width, _ in (width - 150) * 0.38 - 28 }
                    }
                }
            }
            .padding(.horizontal, 75)
            .padding(.top, 70)
            .padding(.bottom, 90)
        }
        .scrollIndicators(.automatic)
        .overlay { CornerLabels(folder: folder, count: children.count) }
    }

    private func grid(_ items: [BoardItem], columns: Int) -> some View {
        MasonryLayout(columns: columns, spacing: 16) {
            ForEach(items) { item in
                HeroSlot(id: item.id, context: hero) {
                    Button { onOpenItem(item.id) } label: {
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
        }
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

/// Etiquetas monoespaçadas nos quatro cantos da coleção, como no conceito.
private struct CornerLabels: View {
    let folder: BoardItem
    let count: Int

    var body: some View {
        ZStack {
            Text((folder.tag ?? "Pasta").uppercased())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.paper, in: .rect(cornerRadius: 4))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 16)
            Text(folder.title.uppercased())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            Text("Criada em \(folder.createdAt.formatted(.dateTime.day().month(.wide)))".uppercased())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            Text((count == 1 ? "1 item" : "\(count) itens").uppercased())
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, -14)
        }
        .font(.label)
        .foregroundStyle(.secondary)
        .padding(18)
        .allowsHitTesting(false)
    }
}
