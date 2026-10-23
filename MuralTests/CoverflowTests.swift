import AppKit
import CoreGraphics
import Foundation
import ImageIO
import MuralKit
import SwiftUI
import Testing
import UniformTypeIdentifiers

@testable import Mural

/// A vitrine de murais da barra de menus: as contas da geometria, a conta do gesto de dois dedos e uma imagem para ver.
@Suite("Vitrine de murais")
struct CoverflowTests {
    private let geometry = CoverflowGeometry()

    private func transform(_ d: Int, reduceMotion: Bool = false) -> CoverflowGeometry.Transform {
        geometry.transform(forOffset: d, reduceMotion: reduceMotion)
    }

    // MARK: Geometria

    @Test("A capa do centro fica de frente, inteira e por cima de todas")
    func centerIsFlatAndOnTop() {
        let center = transform(0)

        #expect(center == CoverflowGeometry.Transform(offsetX: 0, angle: 0, scale: 1, zIndex: 5, opacity: 1))
        for d in -6...6 where d != 0 {
            #expect(center.zIndex > transform(d).zIndex)
        }
    }

    @Test("As laterais são espelhadas: deslocamento e giro opostos, o resto igual")
    func sidesAreMirrored() {
        for distance in 1...6 {
            let left = transform(-distance)
            let right = transform(distance)

            #expect(left.offsetX == -right.offsetX)
            #expect(left.angle == -right.angle)
            #expect(left.scale == right.scale)
            #expect(left.zIndex == right.zIndex)
            #expect(left.opacity == right.opacity)
        }
    }

    @Test("O deslocamento parte do vão do centro e cresce o espaçamento das laterais")
    func offsetsFollowTheGaps() {
        #expect([1, 2, 3, 4].map { transform($0).offsetX } == [175, 223, 271, 319])
        #expect([-1, -2, -3, -4].map { transform($0).offsetX } == [-175, -223, -271, -319])
    }

    @Test("A esquerda gira para um lado e a direita para o outro, na escala das laterais")
    func sidesTurnTowardTheCenter() {
        #expect(transform(-1).angle == 58)
        #expect(transform(1).angle == -58)
        #expect(transform(-3).scale == 0.78)
        #expect(transform(3).scale == 0.78)
    }

    @Test("A ordem de empilhamento cai com a distância ao centro")
    func zIndexFallsWithDistance() {
        let order = (0...4).map { transform($0).zIndex }

        #expect(order == [5, 4, 3, 2, 1])
        #expect(zip(order, order.dropFirst()).allSatisfy { $0 > $1 })
    }

    @Test("A opacidade cai a cada passo e é zero além das laterais visíveis")
    func opacityFallsAndVanishesBeyondTheVisible() {
        let visible = (0...4).map { transform($0).opacity }
        let expected = [1, 1, 0.85, 0.7, 0.55]

        for (actual, wanted) in zip(visible, expected) {
            #expect(abs(actual - wanted) < 1e-9, "\(actual) em vez de \(wanted)")
        }
        for d in [5, 6, 20, -5, -6, -20] {
            #expect(transform(d).opacity == 0, "d = \(d)")
        }
        // Mesmo transparente, a capa fica onde a regra a põe, para entrar e sair sem pular.
        #expect(transform(5).offsetX == 367)
        #expect(transform(5).scale == 0.78)
    }

    @Test("Reduzir Movimento tira o giro e usa a escala 0,85 nas laterais, sem mexer no resto")
    func reduceMotionDropsTheTurn() {
        for d in -6...6 {
            let calm = transform(d, reduceMotion: true)
            let normal = transform(d)

            #expect(calm.offsetX == normal.offsetX)
            #expect(calm.zIndex == normal.zIndex)
            #expect(calm.opacity == normal.opacity)
            #expect(calm.angle == 0)
            #expect(calm.scale == (d == 0 ? 1 : 0.85), "d = \(d)")
        }
    }

    @Test("Menos laterais visíveis mudam o topo da pilha e onde a capa some")
    func customVisibleSideCount() {
        let narrow = CoverflowGeometry(visibleSideCount: 2)

        #expect(narrow.transform(forOffset: 0, reduceMotion: false).zIndex == 3)
        #expect(narrow.transform(forOffset: 2, reduceMotion: false).opacity > 0)
        #expect(narrow.transform(forOffset: 3, reduceMotion: false).opacity == 0)
    }

    @Test("O intervalo visível é a seleção com quatro de cada lado, preso à lista")
    func visibleRangeIsClampedToTheList() {
        #expect(geometry.visibleRange(selection: 0, count: 20) == 0..<5)
        #expect(geometry.visibleRange(selection: 2, count: 20) == 0..<7)
        #expect(geometry.visibleRange(selection: 10, count: 30) == 6..<15)
        #expect(geometry.visibleRange(selection: 19, count: 20) == 15..<20)
        #expect(geometry.visibleRange(selection: 1, count: 3) == 0..<3)
    }

    @Test("Lista vazia dá intervalo vazio, e uma seleção fora da lista vale a ponta mais próxima")
    func visibleRangeHandlesEmptyAndStaleSelection() {
        #expect(geometry.visibleRange(selection: 0, count: 0).isEmpty)
        #expect(geometry.visibleRange(selection: 7, count: 0).isEmpty)
        #expect(geometry.visibleRange(selection: 50, count: 3) == 0..<3)
        #expect(geometry.visibleRange(selection: -4, count: 20) == 0..<5)
        #expect(geometry.visibleRange(selection: 99, count: 20) == 15..<20)
    }

    @Test("As capas são pedidas da seleção para fora, uma a mais que as visíveis")
    func priorityOrderGoesOutwardFromTheSelection() {
        #expect(geometry.priorityOrder(selection: 10, count: 30) == [10, 11, 9, 12, 8, 13, 7, 14, 6, 15, 5])
    }

    @Test("A ordem de pedido só tem índices que existem, sem repetir")
    func priorityOrderKeepsToValidIndexes() {
        #expect(geometry.priorityOrder(selection: 0, count: 20) == [0, 1, 2, 3, 4, 5])
        #expect(geometry.priorityOrder(selection: 19, count: 20) == [19, 18, 17, 16, 15, 14])
        #expect(geometry.priorityOrder(selection: 1, count: 3) == [1, 2, 0])
        #expect(geometry.priorityOrder(selection: 0, count: 1) == [0])
        #expect(geometry.priorityOrder(selection: 0, count: 0).isEmpty)
        #expect(geometry.priorityOrder(selection: 9, count: 3) == [2, 1, 0])

        for (selection, count) in [(0, 7), (3, 7), (6, 7), (12, 40)] {
            let order = geometry.priorityOrder(selection: selection, count: count)
            #expect(order.allSatisfy { (0..<count).contains($0) }, "seleção \(selection) de \(count): \(order)")
            #expect(Set(order).count == order.count, "seleção \(selection) de \(count): \(order)")
        }
    }

    // MARK: Gesto

    @Test("40 pontos para a esquerda dão um passo para o mural seguinte")
    func fortyPointsMakeOneStep() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: -40, deltaY: 0, isPrecise: true) == 1)
        #expect(accumulator.travelled == 0)
    }

    @Test("Menos de 40 pontos esperam o resto do gesto")
    func smallDeltasAccumulate() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: -25, deltaY: 2, isPrecise: true) == 0)
        #expect(accumulator.add(deltaX: -10, deltaY: 1, isPrecise: true) == 0)
        #expect(accumulator.add(deltaX: -5, deltaY: 0, isPrecise: true) == 1)
    }

    @Test("100 pontos dão dois passos e guardam os 20 que sobram")
    func longSwipeStepsSeveralTimesAndKeepsTheRemainder() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: -100, deltaY: 0, isPrecise: true) == 2)
        #expect(accumulator.travelled == -20)
        #expect(accumulator.add(deltaX: -20, deltaY: 0, isPrecise: true) == 1)
        #expect(accumulator.travelled == 0)
    }

    @Test("Arrastar para a direita volta ao mural anterior, em quantos passos o gesto valer")
    func rightwardSwipeGoesBack() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: 40, deltaY: 0, isPrecise: true) == -1)
        #expect(accumulator.add(deltaX: 130, deltaY: 0, isPrecise: true) == -3)
        #expect(accumulator.travelled == 10)
    }

    @Test("Mudar de sentido no meio do gesto desfaz o que estava a caminho")
    func reversingCancelsPendingTravel() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: -30, deltaY: 0, isPrecise: true) == 0)
        #expect(accumulator.add(deltaX: 30, deltaY: 0, isPrecise: true) == 0)
        #expect(accumulator.travelled == 0)
    }

    @Test("Na roda de mouse cada evento é um passo, seja qual for o tamanho")
    func mouseWheelStepsOncePerEvent() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: -1, deltaY: 0, isPrecise: false) == 1)
        #expect(accumulator.add(deltaX: -5, deltaY: 0, isPrecise: false) == 1)
        #expect(accumulator.add(deltaX: 2, deltaY: 0, isPrecise: false) == -1)
        #expect(accumulator.travelled == 0)
    }

    @Test("Rolagem mais vertical que horizontal é ignorada e não acumula")
    func verticalScrollIsIgnored() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: -30, deltaY: 120, isPrecise: true) == 0)
        #expect(accumulator.add(deltaX: 300, deltaY: -400, isPrecise: true) == 0)
        #expect(accumulator.add(deltaX: -3, deltaY: 5, isPrecise: false) == 0)
        #expect(accumulator.travelled == 0)
        #expect(accumulator == SwipeAccumulator())

        // Depois da vertical, a horizontal começa do zero.
        #expect(accumulator.add(deltaX: -30, deltaY: 0, isPrecise: true) == 0)
        #expect(accumulator.travelled == -30)
    }

    @Test("Só a rolagem com algo na horizontal é do gesto; o resto segue para quem rola na vertical")
    func onlyHorizontalScrollIsClaimed() {
        #expect(SwipeAccumulator.isHorizontal(deltaX: -10, deltaY: 3))
        #expect(SwipeAccumulator.isHorizontal(deltaX: 10, deltaY: -10))
        #expect(!SwipeAccumulator.isHorizontal(deltaX: 3, deltaY: 10))
        #expect(!SwipeAccumulator.isHorizontal(deltaX: 0, deltaY: 0))
        #expect(!SwipeAccumulator.isHorizontal(deltaX: 0, deltaY: 5))
    }

    @Test("Zerar esquece a sobra do gesto")
    func resetForgetsTheRemainder() {
        var accumulator = SwipeAccumulator()
        #expect(accumulator.add(deltaX: -30, deltaY: 0, isPrecise: true) == 0)

        accumulator.reset()

        #expect(accumulator == SwipeAccumulator())
        #expect(accumulator.add(deltaX: -30, deltaY: 0, isPrecise: true) == 0)
        #expect(accumulator.add(deltaX: -10, deltaY: 0, isPrecise: true) == 1)
    }

    @Test("Um delta que não é número não vira passo nem estraga o acumulado")
    func nonFiniteDeltaIsIgnored() {
        var accumulator = SwipeAccumulator()

        #expect(accumulator.add(deltaX: .nan, deltaY: 0, isPrecise: true) == 0)
        #expect(accumulator.add(deltaX: -.infinity, deltaY: 0, isPrecise: true) == 0)
        #expect(accumulator == SwipeAccumulator())
    }

    // MARK: Gesto sobre as capas

    @Test("A rolagem sobre as capas e o título chega à vista do gesto, e o clique segue para o SwiftUI")
    @MainActor
    func scrollReachesTheSwipeViewButClicksPassThrough() throws {
        let entries = (0..<7).map { index in Self.entry(named: "Mural \(index)", updatedHoursAgo: Double(index), route: { .saved($0) }) }
        let root = BoardCoverflow(entries: entries, selection: 3, covers: [:], onSelect: { _ in }, onOpen: { _ in })
            .frame(width: 568)
        let host = NSHostingView(rootView: root)
        let height = BoardCoverflow.height
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 568, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        host.frame = NSRect(x: 0, y: 0, width: 568, height: height)
        host.layoutSubtreeIfNeeded()
        let swipe = try #require(Self.swipeView(in: host))

        // A origem do `hitTest` é embaixo: a capa do centro, uma capa lateral e o título.
        for point in [NSPoint(x: 284, y: height - 75), NSPoint(x: 459, y: height - 90), NSPoint(x: 284, y: height - 230)] {
            swipe.currentEventType = { .scrollWheel }
            #expect(host.hitTest(point) === swipe, "rolagem em \(point)")
            swipe.currentEventType = { .leftMouseDown }
            #expect(host.hitTest(point) === host, "clique em \(point)")
        }
    }

    // MARK: Exemplo para ver

    @Test("Desenha a vitrine com sete murais e capas de cores diferentes, para ser vista")
    @MainActor
    func attachesASampleCoverflow() throws {
        let names = ["Casa", "Viagem", "Estudos", "Receitas", "Trabalho", "Ideias", "Leituras"]
        let hours: [Double] = [1, 5, 26, 52, 24 * 5, 24 * 12, 24 * 40]
        let colors: [(Double, Double, Double)] = [
            (0.93, 0.45, 0.35), (0.98, 0.76, 0.30), (0.45, 0.78, 0.50), (0.30, 0.70, 0.78),
            (0.38, 0.52, 0.90), (0.68, 0.48, 0.88), (0.90, 0.50, 0.70),
        ]
        let entries = names.indices.map { index in
            Self.entry(named: names[index], updatedHoursAgo: hours[index], route: { .saved($0) })
        }
        var covers: [BoardID: CGImage] = [:]
        for (entry, color) in zip(entries, colors) {
            covers[entry.manifest.id] = try Self.cover(red: color.0, green: color.1, blue: color.2)
        }

        let image = try Self.render(entries: entries, selection: 3, covers: covers)

        #expect(image.width == 1200)
        Attachment.record(try Self.pngData(of: image), named: "vitrine-exemplo.png")
    }

    @Test("Desenha a vitrine no começo da lista, com um rascunho no centro e murais sem capa, para ser vista")
    @MainActor
    func attachesASampleCoverflowWithoutCovers() throws {
        let entries = [
            Self.entry(named: "Boas-vindas", updatedHoursAgo: 0, route: { .welcomeDraft($0) }),
            Self.entry(named: "Receitas", updatedHoursAgo: 30, route: { .saved($0) }),
            Self.entry(named: "Um mural com um nome bem longo para conferir a quebra", updatedHoursAgo: 90, route: { .saved($0) }),
        ]
        let covers = [entries[1].manifest.id: try Self.cover(red: 0.30, green: 0.70, blue: 0.78)]

        let image = try Self.render(entries: entries, selection: 0, covers: covers)

        #expect(image.width == 1200)
        Attachment.record(try Self.pngData(of: image), named: "vitrine-sem-capa.png")
    }

    // MARK: Apoio

    private static func entry(
        named name: String, updatedHoursAgo hours: Double, route: (BoardID) -> BoardRoute
    ) -> BoardLibraryEntry {
        let id = BoardID()
        let updated = Date(timeIntervalSinceNow: -hours * 3600)
        return BoardLibraryEntry(
            manifest: BoardManifest(id: id, name: name, createdAt: updated.addingTimeInterval(-86_400), updatedAt: updated),
            route: route(id))
    }

    /// Uma capa de cor sólida (640 × 400, o dobro de 320 × 200) com uma faixa escura perto da base, só para o reflexo
    /// mostrar que está espelhado.
    private static func cover(red: Double, green: Double, blue: Double) throws -> CGImage {
        let width = 640
        let height = 400
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // A origem do contexto é embaixo: a faixa fica rente à base da imagem.
        context.setFillColor(red: red * 0.55, green: green * 0.55, blue: blue * 0.55, alpha: 1)
        context.fill(CGRect(x: 0, y: 36, width: width, height: 28))
        return try #require(context.makeImage())
    }

    /// A vitrine no fundo do painel, na largura dele, em 2x, sem o gesto de AppKit.
    @MainActor
    private static func render(entries: [BoardLibraryEntry], selection: Int, covers: [BoardID: CGImage]) throws -> CGImage {
        let coverflow = BoardCoverflow(
            entries: entries, selection: selection, covers: covers, isInteractive: false, onSelect: { _ in }, onOpen: { _ in }
        )
        .frame(width: 600)
        .background(Theme.canvas)
        let renderer = ImageRenderer(content: coverflow)
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    @MainActor
    private static func swipeView(in view: NSView) -> CoverflowSwipe.SwipeView? {
        if let swipe = view as? CoverflowSwipe.SwipeView { return swipe }
        for subview in view.subviews {
            if let swipe = swipeView(in: subview) { return swipe }
        }
        return nil
    }

    private static func pngData(of image: CGImage) throws -> Data {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
