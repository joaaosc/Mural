import CoreGraphics

/// As contas de onde o painel da barra de menus fica na tela depois que a pessoa o arrasta. Sem AppKit, para serem
/// testadas sem janela nem monitor.
///
/// O que se guarda é o canto de cima à esquerda, e não a moldura: a altura do painel muda com o que há para colar, e um
/// menu cresce para baixo a partir de onde pende. As coordenadas são as do AppKit, com y crescendo para cima, então o
/// canto de cima é o `maxY` da moldura.
nonisolated enum MenuBarPanelPlacement {
    /// A folga, em pontos, para um canto guardado na borda de uma tela ainda contar como dentro dela: o canto de cima de
    /// um painel encostado no alto da área visível cai exatamente no `maxY`, que `CGRect.contains` deixa de fora.
    static let edgeTolerance: CGFloat = 2

    /// A moldura de um painel de tamanho `size` com o canto de cima à esquerda em `topLeft`, presa à área visível da tela
    /// que contém esse canto.
    /// - Returns: `nil` se nenhuma tela contém o canto (o monitor em que o painel ficou foi desligado): o painel volta ao
    ///   lugar de sempre.
    static func frame(size: CGSize, topLeft: CGPoint, visibleFrames: [CGRect]) -> CGRect? {
        guard topLeft.x.isFinite, topLeft.y.isFinite else { return nil }
        let screen = visibleFrames.first {
            $0.insetBy(dx: -edgeTolerance, dy: -edgeTolerance).contains(topLeft)
        }
        guard let screen else { return nil }
        let frame = CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
        return clamped(frame, to: screen)
    }

    /// A moldura empurrada para dentro da área visível, sem mudar de tamanho. Mais alta que a área, fica encostada no alto
    /// dela; mais larga, na borda esquerda.
    static func clamped(_ frame: CGRect, to visibleFrame: CGRect) -> CGRect {
        let x = max(min(frame.minX, visibleFrame.maxX - frame.width), visibleFrame.minX)
        let top = min(max(frame.maxY, visibleFrame.minY + frame.height), visibleFrame.maxY)
        return CGRect(x: x, y: top - frame.height, width: frame.width, height: frame.height)
    }

    /// O canto de cima à esquerda de uma moldura, que é o que se guarda.
    static func topLeft(of frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX, y: frame.maxY)
    }
}
