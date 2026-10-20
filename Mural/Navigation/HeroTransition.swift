import SwiftUI

/// Liga um cartão à tela que ele abre, para a tela "crescer" a partir do cartão.
///
/// No macOS a transição de zoom da navegação não existe; aqui o cartão some e a
/// tela de destino entra na mesma animação, com o mesmo id, e o SwiftUI interpola
/// os dois retângulos. Com Reduzir Movimento ligado, o efeito é desligado.
struct HeroContext {
    var namespace: Namespace.ID
    var isEnabled: Bool
    /// Ids dos cartões abertos agora (o cartão dá lugar a um espaço vazio).
    var presented: Set<UUID>
}

extension View {
    @ViewBuilder
    func heroLink(_ id: UUID, _ context: HeroContext) -> some View {
        if context.isEnabled {
            matchedGeometryEffect(id: id, in: context.namespace)
        } else {
            self
        }
    }
}

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
