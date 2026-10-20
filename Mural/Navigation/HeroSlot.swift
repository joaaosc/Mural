import SwiftUI

/// Mostra o cartão ou, se ele estiver aberto, um espaço vazio do mesmo tamanho.
struct HeroSlot<Content: View>: View {
    let id: UUID
    let context: HeroContext
    @ViewBuilder var content: Content

    var body: some View {
        if context.presented.contains(id) {
            Color.clear
        } else {
            content.heroLink(id, context)
        }
    }
}
