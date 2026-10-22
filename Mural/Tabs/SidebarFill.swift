import SwiftUI

/// Fundo da barra lateral: material encorpado com uma camada da cor de página, para ficar nitidamente mais
/// opaco que o mural ao lado. Com Reduzir Transparência, a cor de página sólida.
struct SidebarFill: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Quanto da cor de página cobre o material.
    private static let pageTint = 0.45

    var body: some View {
        if reduceTransparency {
            Theme.page
        } else {
            Rectangle().fill(.ultraThickMaterial).overlay(Theme.page.opacity(Self.pageTint))
        }
    }
}
