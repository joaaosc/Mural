import CoreGraphics

/// As contas da vitrine de murais (coverflow): onde cada capa fica, quanto gira e quanto some, conforme a distância
/// até a capa selecionada. Sem SwiftUI, para serem testadas sem desenhar nada.
///
/// Nas funções abaixo, `d` é o deslocamento do índice da capa em relação à seleção: 0 é a capa do centro, negativo
/// fica à esquerda e positivo, à direita.
nonisolated struct CoverflowGeometry: Equatable, Sendable {
    /// O tamanho da capa de frente, em pontos. Mantém a proporção 8:5 da capa do mural (320 × 200).
    var coverSize = CGSize(width: 240, height: 150)
    /// A escala das capas laterais.
    var sideScale: CGFloat = 0.78
    /// O giro das capas laterais, em graus.
    var sideAngle: Double = 58
    /// A distância, de centro a centro, entre a capa do meio e a primeira lateral.
    var centerGap: CGFloat = 175
    /// A distância, de centro a centro, entre uma lateral e a seguinte.
    var sideSpacing: CGFloat = 48
    /// Quantas laterais aparecem de cada lado da capa do meio.
    var visibleSideCount = 4

    /// A escala das laterais com Reduzir Movimento: sem o giro, elas ficam um pouco maiores para ainda ler como capas.
    static let reducedMotionSideScale: CGFloat = 0.85
    /// O véu escuro sobre a primeira capa lateral, de 0 a 1: forte o bastante para a do meio se destacar como a
    /// escolhida, sem esconder o que as laterais mostram.
    static let sideDimming = 0.08
    /// Quanto o véu escurece a cada passo além da primeira lateral.
    static let dimmingFalloff = 0.03

    /// Como uma capa é posta no palco.
    struct Transform: Equatable, Sendable {
        /// O deslocamento horizontal em relação ao centro do palco.
        var offsetX: CGFloat
        /// O giro em torno do eixo vertical, em graus: positivo nas capas da esquerda, negativo nas da direita.
        var angle: Double
        var scale: CGFloat
        /// A ordem de empilhamento: a capa do meio fica por cima, e cada lateral fica abaixo da anterior.
        var zIndex: Double
        var opacity: Double
        /// O véu escuro sobre a capa, de 0 a 1: zero na do meio, ``CoverflowGeometry/sideDimming`` na primeira lateral e
        /// mais escuro a cada passo para fora.
        var dimming: Double = 0
    }

    /// Onde e como desenhar a capa que está `d` posições da seleção.
    ///
    /// Além de `visibleSideCount` a capa já é transparente: mantém o deslocamento e a escala da regra, só some. Com
    /// Reduzir Movimento as laterais não giram e usam ``reducedMotionSideScale``. As laterais ganham o véu de
    /// ``sideDimming``, mais ``dimmingFalloff`` a cada passo, para a capa escolhida ser a única sem ele.
    func transform(forOffset d: Int, reduceMotion: Bool) -> Transform {
        let distance = abs(d)
        guard distance > 0 else {
            return Transform(offsetX: 0, angle: 0, scale: 1, zIndex: Double(visibleSideCount + 1), opacity: 1)
        }
        let direction: CGFloat = d < 0 ? -1 : 1
        let angle = d < 0 ? sideAngle : -sideAngle
        return Transform(
            offsetX: direction * (centerGap + CGFloat(distance - 1) * sideSpacing),
            angle: reduceMotion ? 0 : angle,
            scale: reduceMotion ? Self.reducedMotionSideScale : sideScale,
            zIndex: Double(visibleSideCount + 1 - distance),
            opacity: distance > visibleSideCount ? 0 : 1,
            dimming: min(0.17, Self.sideDimming + Self.dimmingFalloff * Double(distance - 1))
        )
    }

    /// Os índices que a vitrine desenha: a seleção e `visibleSideCount` para cada lado, presos à lista.
    ///
    /// Uma seleção fora da lista (um mural que acabou de sair) conta como a ponta mais próxima, e a lista vazia dá
    /// um intervalo vazio.
    func visibleRange(selection: Int, count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let center = Self.clamped(selection, count: count)
        let reach = max(0, visibleSideCount)
        return max(0, center - reach)..<min(count, center + reach + 1)
    }

    /// A ordem para pedir as capas: a seleção, o seguinte, o anterior, e assim para fora, até um passo além do que
    /// aparece, para a próxima capa já estar pronta quando a seleção andar. Só índices que existem.
    func priorityOrder(selection: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let center = Self.clamped(selection, count: count)
        var order = [center]
        for distance in stride(from: 1, through: visibleSideCount + 1, by: 1) {
            for index in [center + distance, center - distance] where (0..<count).contains(index) {
                order.append(index)
            }
        }
        return order
    }

    private static func clamped(_ selection: Int, count: Int) -> Int {
        min(max(selection, 0), count - 1)
    }
}
