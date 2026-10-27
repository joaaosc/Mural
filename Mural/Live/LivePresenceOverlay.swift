import MuralKit
import SwiftUI

/// As oito cores das pessoas no Live Share, na ordem de `LivePresence.colorIndex(for:)`: a mesma pessoa tem a mesma cor em todos os Macs.
nonisolated enum LivePalette {
    static let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .red, .indigo]

    /// A cor do lugar `index` da paleta; um índice fora da faixa volta ao começo.
    static func color(_ index: Int) -> Color {
        let count = colors.count
        return colors[((index % count) + count) % count]
    }
}

/// A camada de presença de um mural: lê as pessoas do Live Share no controlador do ambiente e só desenha quando há alguém. Sem
/// controlador ou sem pessoas, não é nada.
struct LivePresenceLayer: View {
    let boardID: BoardID
    let model: BoardModel
    let zoom: CGFloat

    @Environment(LiveShareController.self) private var liveShare: LiveShareController?

    var body: some View {
        if let liveShare {
            let peers = liveShare.peers(on: boardID)
            if !peers.isEmpty {
                LivePresenceOverlay(peers: peers, model: model, zoom: zoom)
            }
        } else {
            EmptyView()
        }
    }
}

/// O que as outras pessoas fazem no mural, em pontos do mural (mesmo espaço dos cartões, antes do zoom): o cursor de quem aponta, o
/// fantasma de quem arrasta e o selo do cartão que alguém abriu. Só desenha: o toque passa direto para o mural.
///
/// Cursores e selos têm sempre o mesmo tamanho na tela (`1 / zoom` desfaz o zoom do mural); o fantasma é do tamanho do cartão.
struct LivePresenceOverlay: View {
    let peers: [LivePeer]
    let model: BoardModel
    let zoom: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// O vão, na tela, entre um selo e o canto do que ele marca.
    private static let tagGap: CGFloat = 3
    /// O arredondamento do fantasma, em pontos do mural.
    private static let ghostRadius: CGFloat = 14

    var body: some View {
        // De baixo para cima: fantasmas, selos dos cartões abertos e, por cima de tudo, os cursores.
        ZStack(alignment: .topLeading) {
            ForEach(peers) { peer in ghost(of: peer) }
            ForEach(peers) { peer in openCardTag(of: peer) }
            ForEach(peers) { peer in cursor(of: peer) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Marcas

    /// Quem está arrastando mostra onde o elemento vai ficar: o retângulo do tamanho dele, na cor da pessoa, com o nome no canto.
    /// Sem o elemento neste Mac, nada.
    @ViewBuilder
    private func ghost(of peer: LivePeer) -> some View {
        if let drag = peer.drag, let size = size(of: drag) {
            let color = LivePalette.color(peer.colorIndex)
            let shape = RoundedRectangle(cornerRadius: Self.ghostRadius, style: .continuous)
            ZStack(alignment: .topLeading) {
                shape
                    .fill(color.opacity(0.15))
                    .overlay { shape.strokeBorder(color, lineWidth: 2 / zoom) }
                    .frame(width: size.width, height: size.height)
                    .offset(x: drag.x, y: drag.y)
                LiveNameTag(name: peer.name, symbolName: nil, color: color)
                    .pinned(above: CGPoint(x: drag.x, y: drag.y - Self.tagGap / zoom), zoom: zoom)
            }
        }
    }

    /// O selo de quem abriu um cartão solto (ou um texto livre): logo acima do canto superior esquerdo dele, com o lápis (editando)
    /// ou o olho (vendo). Cartão dentro de uma pasta não tem lugar no mural: sem selo.
    @ViewBuilder
    private func openCardTag(of peer: LivePeer) -> some View {
        if let focus = peer.focus, let corner = corner(of: focus) {
            LiveNameTag(name: peer.name, symbolName: focus.isEditing ? "pencil" : "eye", color: LivePalette.color(peer.colorIndex))
                .pinned(above: CGPoint(x: corner.x, y: corner.y - Self.tagGap / zoom), zoom: zoom)
        }
    }

    /// O cursor de quem não está arrastando: a seta com a ponta no ponto e o nome ao lado. Os movimentos se emendam em ~0,08 s.
    @ViewBuilder
    private func cursor(of peer: LivePeer) -> some View {
        if peer.drag == nil, let point = peer.pointer {
            LiveCursor(name: peer.name, color: LivePalette.color(peer.colorIndex))
                .pinned(at: point, zoom: zoom)
                .animation(reduceMotion ? nil : .linear(duration: 0.08), value: point)
        }
    }

    // MARK: Lugar dos elementos

    /// O tamanho do elemento arrastado neste Mac (`BoardLayout.size(of:)`); `nil` quando ele não está aqui.
    private func size(of drag: LiveDrag) -> CGSize? {
        switch drag.kind {
        case .item:
            guard let item = model.item(id: drag.id) else { return nil }
            let size = BoardLayout.size(of: item)
            return CGSize(width: size.width, height: size.height)
        case .freeText:
            guard let freeText = model.freeText(id: drag.id) else { return nil }
            let size = BoardLayout.size(of: freeText)
            return CGSize(width: size.width, height: size.height)
        }
    }

    /// O canto superior esquerdo do cartão aberto: só de cartão solto ou texto livre deste Mac.
    private func corner(of focus: LiveFocus) -> CGPoint? {
        if let item = model.item(id: focus.itemID) {
            guard item.parentID == nil else { return nil }
            return CGPoint(x: item.position.x, y: item.position.y)
        }
        if let freeText = model.freeText(id: focus.itemID) {
            return CGPoint(x: freeText.position.x, y: freeText.position.y)
        }
        return nil
    }
}

// MARK: Peças

/// A seta do cursor, com a ponta na origem do quadro (13 × 19 pontos).
private nonisolated struct LiveCursorArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 16.5))
        path.addLine(to: CGPoint(x: 4.2, y: 12.6))
        path.addLine(to: CGPoint(x: 6.9, y: 18.8))
        path.addLine(to: CGPoint(x: 9.6, y: 17.6))
        path.addLine(to: CGPoint(x: 6.9, y: 11.6))
        path.addLine(to: CGPoint(x: 12, y: 11.6))
        path.closeSubpath()
        return path
    }
}

/// O cursor de uma pessoa: a seta na cor dela, com borda branca fina, e o nome numa cápsula ao lado. A ponta fica na origem.
private struct LiveCursor: View {
    let name: String
    let color: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            LiveCursorArrow()
                .fill(color)
                .overlay { LiveCursorArrow().stroke(.white, style: StrokeStyle(lineWidth: 1, lineJoin: .round)) }
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                .frame(width: 13, height: 19, alignment: .topLeading)
            LiveNameTag(name: name, symbolName: nil, color: color)
                .offset(x: 11, y: 15)
        }
    }
}

/// A cápsula com o nome da pessoa: texto branco sobre a cor dela, com um símbolo antes quando há (lápis, olho).
private struct LiveNameTag: View {
    let name: String
    let symbolName: String?
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(name)
                .lineLimit(1)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.white)
        .frame(maxWidth: 160)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(color, in: .capsule)
    }
}

extension View {
    /// Põe o canto superior esquerdo da vista no ponto, em pontos do mural, com o tamanho de sempre na tela: o zoom do mural é desfeito
    /// (`1 / zoom`) em volta desse canto. Não ocupa lugar no layout: todas as marcas partem da origem do mural.
    fileprivate func pinned(at point: CGPoint, zoom: CGFloat) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: .topLeading) {
                self.fixedSize().scaleEffect(1 / zoom, anchor: .topLeading)
            }
            .offset(x: point.x, y: point.y)
    }

    /// O mesmo, com o canto inferior esquerdo da vista no ponto: a vista fica logo acima dele.
    fileprivate func pinned(above point: CGPoint, zoom: CGFloat) -> some View {
        Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: .bottomLeading) {
                self.fixedSize().scaleEffect(1 / zoom, anchor: .bottomLeading)
            }
            .offset(x: point.x, y: point.y)
    }
}

// MARK: Previews

#if DEBUG
#Preview("Presença", traits: .fixedLayout(width: 760, height: 520)) {
    LivePresenceSample(zoom: 1)
}

#Preview("Presença (escuro)", traits: .fixedLayout(width: 760, height: 520)) {
    LivePresenceSample(zoom: 1)
        .preferredColorScheme(.dark)
}

#Preview("Presença, zoom 50%", traits: .fixedLayout(width: 760, height: 520)) {
    LivePresenceSample(zoom: 0.5)
}

/// O mural de exemplo com três pessoas: a Bia com o cursor, o Caio arrastando um cartão e a Dani com um cartão aberto. Os cartões são
/// retângulos no lugar dos de verdade, só para mostrar onde as marcas caem.
private struct LivePresenceSample: View {
    let zoom: CGFloat
    @State private var model = BoardModel.preview()

    var body: some View {
        let items = Array(model.rootItems.prefix(4))
        let extent = model.rootExtent
        let boardSize = CGSize(width: max(extent.width, 720) + 40, height: max(extent.height, 480) + 40)
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            ForEach(items) { item in
                let size = BoardLayout.size(of: item)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: size.width, height: size.height)
                    .offset(x: item.position.x, y: item.position.y)
            }
            LivePresenceOverlay(peers: peers(for: items), model: model, zoom: zoom)
        }
        .frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading)
        .scaleEffect(zoom, anchor: .topLeading)
        .frame(width: boardSize.width * zoom, height: boardSize.height * zoom, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func peers(for items: [BoardItem]) -> [LivePeer] {
        func peer(_ index: Int, _ name: String, color: Int) -> LivePeer {
            LivePeer(
                id: UUID(uuidString: "0000000\(index)-0000-4000-8000-000000000000")!, name: name, userRecordName: name.lowercased(),
                isVerified: true, colorIndex: color)
        }
        var bia = peer(1, "Bia", color: 1)
        var caio = peer(2, "Caio", color: 4)
        var dani = peer(3, "Dani", color: 2)
        if let first = items.first {
            let size = BoardLayout.size(of: first)
            bia.pointer = CGPoint(x: first.position.x + size.width * 0.6, y: first.position.y + size.height * 0.45)
        }
        if items.count > 1 {
            let second = items[1]
            caio.drag = LiveDrag(kind: .item, id: second.id, x: second.position.x + 60, y: second.position.y + 40)
        }
        if items.count > 2 {
            dani.focus = LiveFocus(itemID: items[2].id, isEditing: true)
        }
        return [bia, caio, dani]
    }
}
#endif
