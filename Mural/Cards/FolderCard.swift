import MuralKit
import SwiftUI

/// Pasta: duas folhas empilhadas com etiqueta e título; até três dos cartões mais recentes de dentro
/// saem em leque pela borda direita, atrás das folhas.
struct FolderCard: View {
    let folder: BoardItem
    let itemCount: Int
    /// Os cartões mais recentes de dentro, do mais antigo ao mais novo: o último fica por cima dos outros.
    let peeks: [FolderPeekItem]

    /// Uma posição do leque.
    private struct FanSlot {
        /// Inclinação em graus; positivo gira no sentido horário.
        let angle: Double
        /// Quanto a miniatura anda para a direita a partir de encostar na borda da pasta.
        let offset: CGFloat
        /// Quanto a miniatura desce (positivo) ou sobe a partir do meio da pasta: cada uma mostra um canto diferente.
        let lift: CGFloat
    }

    /// Tamanho de cada miniatura do leque.
    private static let fanTileSize = CGSize(width: 60, height: 84)
    /// As posições do leque, do cartão mais antigo ao mais novo. Com menos cartões valem as últimas:
    /// o mais novo sempre fica na última posição.
    private static let fanSlots = [
        FanSlot(angle: -6, offset: 12, lift: -14),
        FanSlot(angle: 2, offset: 24, lift: 0),
        FanSlot(angle: 10, offset: 36, lift: 14),
    ]

    /// Quanto o leque passa da borda direita da pasta, contando a inclinação de cada miniatura.
    /// O mural usa isso para deixar a prévia da pasta longe do leque.
    static let fanReach: CGFloat = {
        let halfWidth = fanTileSize.width / 2
        let halfHeight = fanTileSize.height / 2
        let reaches = fanSlots.map { slot -> CGFloat in
            let angle = CGFloat(Angle.degrees(abs(slot.angle)).radians)
            // A caixa que envolve a miniatura girada passa da miniatura reta por esta diferença, de cada lado.
            return slot.offset + halfWidth * (cos(angle) - 1) + halfHeight * sin(angle)
        }
        return (reaches.max() ?? 0).rounded(.up)
    }()

    var body: some View {
        ZStack {
            fan
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .fill(Theme.paperBack)
                .offset(x: 6)
                .cardShadow()
            front
        }
    }

    /// Os cartões saem pela borda direita, cada um um pouco mais longe e mais inclinado que o anterior.
    /// O leque é só enfeite: a contagem de itens fica no texto do cartão.
    private var fan: some View {
        let shown = Array(peeks.suffix(Self.fanSlots.count))
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, peek in
                let slot = Self.fanSlots[Self.fanSlots.count - shown.count + index]
                FolderPeekTile(item: peek, size: Self.fanTileSize)
                    .rotationEffect(.degrees(slot.angle))
                    .offset(x: slot.offset, y: slot.lift)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private var front: some View {
        VStack(alignment: .leading, spacing: 2) {
            Capsule()
                .fill(.quaternary)
                .frame(width: 28, height: 8)
            Spacer(minLength: 0)
            Text(folder.tag ?? "Pasta")
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
            Text(folder.title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(2)
            Text(itemCount == 1 ? "1 item" : "\(itemCount) itens")
                .font(.system(size: 6))
                .foregroundStyle(.tertiary)
        }
        .paperSheet()
    }
}

#if DEBUG
/// Pastas com 0, 1, 2 e 3 itens de tipos misturados, lado a lado e com o espaço que o mural dá ao leque.
private struct FolderCardGallery: View {
    private let columns: [(title: String, peeks: [FolderPeekItem])]

    init() {
        let photo = Self.photo("Terracota", colors: [Color(red: 0.93, green: 0.42, blue: 0.33), Color(red: 0.45, green: 0.22, blue: 0.16)])
        let sticky = FolderPeekItem(
            id: UUID(), kind: .sticky, title: "Só luz quente", fileURL: nil, stickyColor: .pink)
        let note = FolderPeekItem(
            id: UUID(), kind: .text, title: "Visita à obra", fileURL: nil, stickyColor: nil)
        columns = [
            ("Vazia", []),
            ("Uma foto", [photo]),
            ("Foto e post-it", [photo, sticky]),
            ("Foto, post-it e nota", [photo, sticky, note]),
        ]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14 + FolderCard.fanReach) {
            ForEach(columns, id: \.title) { column in
                FolderCard(
                    folder: BoardItem(kind: .folder, title: column.title),
                    itemCount: column.peeks.count,
                    peeks: column.peeks
                )
                .frame(width: 120, height: 160)
            }
        }
        .padding(40)
        .background(Theme.canvas)
    }

    /// Foto de exemplo: uma imagem gerada na hora, gravada numa pasta temporária.
    private static func photo(_ title: String, colors: [Color]) -> FolderPeekItem {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MuralFolderCard-\(UUID().uuidString).png")
        if let data = PreviewImages.png(colors: colors, size: CGSize(width: 600, height: 900)) {
            try? data.write(to: url)
        }
        return FolderPeekItem(id: UUID(), kind: .image, title: title, fileURL: url, stickyColor: nil)
    }
}

#Preview("Leque de 0 a 3 itens", traits: .fixedLayout(width: 860, height: 260)) {
    FolderCardGallery()
}

#Preview("Leque no escuro", traits: .fixedLayout(width: 860, height: 260)) {
    FolderCardGallery()
        .preferredColorScheme(.dark)
}
#endif
