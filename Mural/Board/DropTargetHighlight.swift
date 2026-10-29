import MuralKit
import SwiftUI

/// Quanto a pasta já está pronta para receber o cartão arrastado.
enum DropHighlightState: Equatable {
    /// Nenhum cartão sobre a pasta.
    case none
    /// Cartão sobre a pasta, ainda esperando o tempo de liberar: destaque leve.
    case pending
    /// Pasta liberada: soltar guarda o cartão nela.
    case armed
}

extension View {
    /// Destaca a pasta que receberia o cartão arrastado: contorno na cor de destaque (leve enquanto
    /// espera, completo quando liberada) e leve aumento ao liberar (sem aumento com Reduzir Movimento).
    func dropTargetHighlight(_ state: DropHighlightState) -> some View {
        modifier(DropTargetHighlight(state: state))
    }
}

private struct DropTargetHighlight: ViewModifier {
    var state: DropHighlightState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if state != .none {
                    // À direita a folga é maior para abraçar também a folha de trás da pasta.
                    RoundedRectangle(cornerRadius: Theme.cardCorner + 3)
                        .strokeBorder(.tint.opacity(state == .armed ? 1 : 0.35), lineWidth: state == .armed ? 2 : 1.5)
                        .padding(EdgeInsets(top: -3, leading: -3, bottom: -3, trailing: -9))
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(state == .armed && !reduceMotion ? 1.04 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: state)
    }
}

#Preview("Pasta como destino") {
    let folder = BoardItem(kind: .folder, title: "44th Street", tag: "CLIENT 002")
    HStack(spacing: 40) {
        FolderCard(folder: folder, itemCount: 3, peeks: [])
            .frame(width: 120, height: 160)
        FolderCard(folder: folder, itemCount: 3, peeks: [])
            .frame(width: 120, height: 160)
            .dropTargetHighlight(.pending)
        FolderCard(folder: folder, itemCount: 3, peeks: [])
            .frame(width: 120, height: 160)
            .dropTargetHighlight(.armed)
    }
    .padding(40)
    .background(Theme.canvas)
}
