import AppKit
import SwiftUI

/// O conteúdo do painel da barra de menus.
///
/// Por ora só o corpo curto e o rodapé com as saídas. A lista de murais entra depois, sem mudar a moldura.
struct MenuBarPanelView: View {
    let tabs: MuralTabs
    /// Fecha o painel em que a vista está.
    ///
    /// Injetado, e não lido do ambiente: o painel é um `NSPanel` aberto pelo ícone, não uma cena do SwiftUI, e não há
    /// uma ação `dismiss` para ler.
    let close: @MainActor () -> Void
    /// Pede ao painel que tome a nova altura do conteúdo. Injetado pelo mesmo motivo de `close`: o painel é do AppKit e
    /// não acompanha o conteúdo sozinho. Ainda sem uso, porque o conteúdo de agora tem altura fixa.
    let resize: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Murais")
                    .font(.headline)
                Text("Escolha um mural e cole o que você copiou.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(PanelMetrics.contentPadding)

            Divider()
            footer
        }
        .frame(width: PanelMetrics.panelWidth)
        .onExitCommand { close() }
    }

    /// A fileira de saídas.
    ///
    /// Nada daqui entra na ordem do Tab: o teclado do painel é do conteúdo, e estes são alvos de clique.
    /// `focusable(false)` é o que diz isso.
    private var footer: some View {
        HStack {
            Button("Novo mural…", systemImage: "plus") {
                close()
                tabs.requestNewBoard()
            }
            .focusable(false)
            .help("Criar um mural novo")
            .accessibilityIdentifier("menu-bar-new-board")

            Button("Todos os murais", systemImage: "sidebar.left") {
                close()
                tabs.showAllMurals()
            }
            .focusable(false)
            .help("Mostrar a janela do Mural com a lista de todos os murais")
            .accessibilityIdentifier("menu-bar-show-all")

            Spacer()

            Button("Sair do Mural", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .labelStyle(.iconOnly)
            .focusable(false)
            .help("Sair do Mural")
            .accessibilityIdentifier("menu-bar-quit")
        }
        .buttonStyle(.borderless)
        .padding(PanelMetrics.contentPadding)
    }
}
