import SwiftUI

/// O fundo do painel da barra de menus, por onde a pessoa o arrasta pela tela.
///
/// Fica atrás do conteúdo: só o que não é capa, botão ou texto leva ao arrasto, e o clique nas capas e nas linhas segue
/// como antes. `WindowDragGesture` move a janela como a barra de título moveria, e o fim do arrasto avisa por `onEnded`
/// para o lugar ser guardado.
struct PanelDragArea: View {
    /// O arrasto terminou com o painel no lugar novo.
    let onEnded: @MainActor () -> Void

    var body: some View {
        Color.clear
            .contentShape(.rect)
            .gesture(WindowDragGesture().onEnded { _ in onEnded() })
            .accessibilityHidden(true)
    }
}
