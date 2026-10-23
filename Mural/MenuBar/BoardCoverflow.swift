import MuralKit
import SwiftUI

/// A vitrine dos murais da barra de menus: as capas lado a lado, a do centro de frente e as laterais giradas em 3D,
/// cada uma com o reflexo, e o nome do mural do centro embaixo.
///
/// As contas de posição, giro e transparência são de ``CoverflowGeometry``; aqui só se desenha. A altura é fixa
/// (``height``) para o painel saber de antemão quanto espaço dar.
struct BoardCoverflow: View {
    let entries: [BoardLibraryEntry]
    /// O índice do mural do centro.
    let selection: Int
    /// As capas já prontas. Um mural sem capa aparece como um quadro neutro com o nome.
    let covers: [BoardID: CGImage]
    var geometry = CoverflowGeometry()
    /// `false` desenha sem o gesto de AppKit, que o `ImageRenderer` não sabe desenhar (para fora da tela).
    var isInteractive = true
    /// Clique numa lateral, gesto ou teclado: o índice que passa a ser o do centro.
    let onSelect: (Int) -> Void
    /// Clique na capa do centro.
    let onOpen: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A altura da vitrine com a geometria padrão: capa, reflexo, título e subtítulo.
    static let height = totalHeight(for: CoverflowGeometry())

    /// A altura da vitrine para uma geometria: o palco (capa e reflexo), o espaço e o bloco do título.
    static func totalHeight(for geometry: CoverflowGeometry) -> CGFloat {
        stageHeight(for: geometry) + Metrics.captionGap + Metrics.captionHeight
    }

    private static func reflectionHeight(for geometry: CoverflowGeometry) -> CGFloat {
        geometry.coverSize.height * Metrics.reflectionFraction
    }

    private static func stageHeight(for geometry: CoverflowGeometry) -> CGFloat {
        geometry.coverSize.height + Metrics.reflectionSpacing + reflectionHeight(for: geometry)
    }

    private enum Metrics {
        static let cornerRadius: CGFloat = 8
        /// O espaço entre a capa e o reflexo.
        static let reflectionSpacing: CGFloat = 3
        /// A faixa da capa que o reflexo mostra: a mais perto da capa.
        static let reflectionFraction: CGFloat = 0.35
        /// A opacidade do reflexo junto da capa; ele some até ficar transparente na ponta.
        static let reflectionOpacity = 0.28
        static let perspective: CGFloat = 0.5
        static let captionGap: CGFloat = 8
        /// O bloco do título (uma linha) e do subtítulo (uma linha), de altura fixa para a vitrine não mexer.
        static let captionHeight: CGFloat = 36
        static let captionSpacing: CGFloat = 2
        static let captionInset: CGFloat = 24
    }

    /// Uma capa a desenhar. A identidade é a do mural, e não o índice, para a capa seguir o mural se a lista mudar.
    private struct Item: Identifiable {
        let index: Int
        let entry: BoardLibraryEntry

        var id: BoardID { entry.manifest.id }
    }

    var body: some View {
        VStack(spacing: Metrics.captionGap) {
            stage
            caption
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.totalHeight(for: geometry))
        .overlay {
            if isInteractive {
                CoverflowSwipe { step in advance(by: step) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Murais")
        .accessibilityValue(selectedEntry?.manifest.name ?? "")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: advance(by: 1)
            case .decrement: advance(by: -1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Abrir") { onOpen(selection) }
        .accessibilityIdentifier("menu-bar-coverflow")
    }

    // MARK: Palco

    private var stage: some View {
        let center = clampedSelection
        let range = geometry.visibleRange(selection: selection, count: entries.count)
        let items = range.map { Item(index: $0, entry: entries[$0]) }
        return ZStack {
            ForEach(items) { item in
                cover(for: item, offset: item.index - center)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.stageHeight(for: geometry), alignment: .top)
        .animation(PanelMotion.animation(.smooth(duration: 0.3), reduceMotion: reduceMotion), value: selection)
    }

    /// A capa e o reflexo de um mural, postos no palco conforme a distância até o centro.
    private func cover(for item: Item, offset d: Int) -> some View {
        let transform = geometry.transform(forOffset: d, reduceMotion: reduceMotion)
        let coverHeight = geometry.coverSize.height
        return VStack(spacing: Metrics.reflectionSpacing) {
            face(of: item.entry)
                // O grupo vira uma imagem só antes da sombra: sem ele, o texto do quadro neutro ganha sombra própria.
                .compositingGroup()
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
                .contentShape(.rect)
                .onTapGesture {
                    if d == 0 {
                        onOpen(item.index)
                    } else {
                        onSelect(item.index)
                    }
                }
            reflection(of: item.entry)
        }
        // As capas encolhem para o chão (o encontro da capa com o reflexo), e não para o meio, para ficarem todas
        // pousadas na mesma linha.
        .scaleEffect(transform.scale, anchor: UnitPoint(x: 0.5, y: coverHeight / Self.stageHeight(for: geometry)))
        .rotation3DEffect(.degrees(transform.angle), axis: (x: 0, y: 1, z: 0), perspective: Metrics.perspective)
        .offset(x: transform.offsetX)
        .zIndex(transform.zIndex)
        .opacity(transform.opacity)
    }

    /// A capa: a imagem preenchendo o quadro, ou um quadro neutro com o símbolo e o nome quando ainda não há imagem.
    private func face(of entry: BoardLibraryEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        return ZStack {
            if let image = covers[entry.manifest.id] {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholder(for: entry)
            }
        }
        .frame(width: geometry.coverSize.width, height: geometry.coverSize.height)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1) }
    }

    private func placeholder(for entry: BoardLibraryEntry) -> some View {
        ZStack {
            Theme.canvas
            VStack(spacing: 6) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.title2)
                Text(entry.manifest.name)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
        }
    }

    /// A mesma capa de cabeça para baixo, só a faixa mais perto da capa, que esmaece até sumir.
    private func reflection(of entry: BoardLibraryEntry) -> some View {
        face(of: entry)
            .scaleEffect(y: -1)
            // Virada, a faixa de cima da cópia é a de baixo da capa.
            .frame(height: Self.reflectionHeight(for: geometry), alignment: .top)
            .clipped()
            .mask {
                LinearGradient(
                    colors: [.black.opacity(Metrics.reflectionOpacity), .clear],
                    startPoint: .top,
                    endPoint: .bottom)
            }
            .allowsHitTesting(false)
    }

    // MARK: Título

    private var caption: some View {
        VStack(spacing: Metrics.captionSpacing) {
            if let entry = selectedEntry {
                Text(entry.manifest.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(detail(of: entry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Metrics.captionInset)
        .frame(height: Metrics.captionHeight, alignment: .top)
    }

    private func detail(of entry: BoardLibraryEntry) -> String {
        switch entry.route {
        case .welcomeDraft:
            "Rascunho de exemplo"
        case .library, .saved:
            "Editado \(entry.manifest.updatedAt.formatted(.relative(presentation: .named)))"
        }
    }

    // MARK: Seleção

    /// A seleção presa à lista: uma seleção velha (um mural que saiu) não derruba a vitrine.
    private var clampedSelection: Int {
        min(max(selection, 0), max(entries.count - 1, 0))
    }

    private var selectedEntry: BoardLibraryEntry? {
        entries.isEmpty ? nil : entries[clampedSelection]
    }

    /// Anda `step` murais a partir da seleção, parando nas pontas; sem mudança, não avisa.
    private func advance(by step: Int) {
        guard !entries.isEmpty else { return }
        let target = min(max(selection + step, 0), entries.count - 1)
        if target != selection {
            onSelect(target)
        }
    }
}
