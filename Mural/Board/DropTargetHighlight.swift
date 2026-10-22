import MuralKit
import SwiftUI

extension View {
    /// Destaca a pasta que receberia o cartão arrastado: contorno na cor de destaque e leve
    /// aumento (sem aumento com Reduzir Movimento).
    func dropTargetHighlight(_ isActive: Bool) -> some View {
        modifier(DropTargetHighlight(isActive: isActive))
    }
}

private struct DropTargetHighlight: ViewModifier {
    var isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    // À direita a folga é maior para abraçar também a folha de trás da pasta.
                    RoundedRectangle(cornerRadius: Theme.cardCorner + 3)
                        .strokeBorder(.tint, lineWidth: 2)
                        .padding(EdgeInsets(top: -3, leading: -3, bottom: -3, trailing: -9))
                        .allowsHitTesting(false)
                }
            }
            .scaleEffect(isActive && !reduceMotion ? 1.04 : 1)
            .animation(reduceMotion ? nil : .smooth(duration: 0.15), value: isActive)
    }
}

#Preview("Pasta como destino") {
    let folder = BoardItem(kind: .folder, title: "44th Street", tag: "CLIENT 002")
    HStack(spacing: 40) {
        FolderCard(folder: folder, itemCount: 3, peeks: [])
            .frame(width: 120, height: 160)
        FolderCard(folder: folder, itemCount: 3, peeks: [])
            .frame(width: 120, height: 160)
            .dropTargetHighlight(true)
    }
    .padding(40)
    .background(Theme.canvas)
}
