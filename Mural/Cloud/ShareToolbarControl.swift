import MuralKit
import MuralSync
import SwiftUI

/// O botão Compartilhar da barra da janela, no lugar do antigo ícone do iCloud: abre o popover com o estado da sincronização, quem
/// tem acesso e as ações do papel da pessoa no mural. Fica numa cápsula própria, separada do "+" por um espaço fixo da barra.
struct ShareToolbarControl: View {
    /// A largura que o botão e o espaço fixo depois dele ocupam na barra da janela, para a faixa de abas ceder o lugar. Estimada (a
    /// cápsula de vidro e o espaço fixo da barra não têm medida pública), com folga: faixa larga demais empurraria o "+" para o menu
    /// de excesso da barra; larga de menos só deixa um vão. Conferir na janela.
    static let toolbarWidth: CGFloat = 60

    let tab: BoardTab
    let tabs: MuralTabs
    let sync: CloudSyncController
    @Binding var isPresented: Bool

    var body: some View {
        let display = ShareDisplay(tab: tab, sync: sync)
        // O papel e o estado vêm do manifesto, que só se conhece depois de o mural carregar.
        let isLoaded = tab.session.model != nil
        Button {
            isPresented.toggle()
        } label: {
            ShareButtonLabel(symbolName: display.buttonSymbolName, hasWarning: isLoaded && display.status.isWarning)
        }
        .disabled(!isLoaded)
        .help("Compartilhar")
        .accessibilityLabel(isLoaded ? display.accessibilityLabel : "Compartilhar \(tab.title)")
        .accessibilityIdentifier("share-button")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LiveSharePopover(tab: tab, tabs: tabs, sync: sync, dismiss: { isPresented = false })
        }
    }
}

extension ShareDisplay {
    /// O que o botão e o popover mostram do mural da aba, lido agora do manifesto e do controlador.
    @MainActor
    init(tab: BoardTab, sync: CloudSyncController) {
        let id = tab.boardID
        self.init(
            boardName: tab.title, cloud: tab.session.cloud, share: sync.shareStates[id], issue: sync.issues[id],
            isSending: sync.sendingBoards.contains(id), accountAvailable: sync.accountAvailable)
    }
}

/// O popover ligado ao controlador. Lê o estado de dentro do próprio corpo, para acompanhar as mudanças com ele aberto.
private struct LiveSharePopover: View {
    let tab: BoardTab
    let tabs: MuralTabs
    let sync: CloudSyncController
    let dismiss: () -> Void

    var body: some View {
        SharePopover(
            display: ShareDisplay(tab: tab, sync: sync),
            onRemoveFromICloud: { confirm { await tabs.requestRemoveFromICloud(tab.route, name: tab.title) } },
            // Para quem recebeu o convite, o pedido de exclusão já vira "sair do mural".
            onLeave: { confirm { await tabs.requestDelete(tab.route, name: tab.title) } },
            // O convidado de teste é só do iCloud falso dos testes de interface.
            onInviteTestGuest: sync.mode == .inMemory ? { try await sync.inviteTestGuest(to: tab.route) } : nil)
    }

    /// Fecha o popover e pede a confirmação à janela, para o diálogo aparecer sem o popover na frente.
    private func confirm(_ request: @escaping @MainActor () async -> Void) {
        dismiss()
        Task { await request() }
    }
}

/// O ícone do botão: o símbolo do estado e, quando há um problema, um selo laranja no canto.
struct ShareButtonLabel: View {
    let symbolName: String
    let hasWarning: Bool

    var body: some View {
        Label("Compartilhar", systemImage: symbolName)
            .labelStyle(.iconOnly)
            .overlay(alignment: .topTrailing) {
                if hasWarning {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .offset(x: 3, y: -2)
                        .accessibilityHidden(true)
                }
            }
    }
}

// MARK: Previews

#Preview("Botão", traits: .fixedLayout(width: 380, height: 100)) {
    ShareButtonGallery()
}

#Preview("Botão (escuro)", traits: .fixedLayout(width: 380, height: 100)) {
    ShareButtonGallery()
        .preferredColorScheme(.dark)
}

/// O botão sem compartilhar, compartilhado e com aviso, na cápsula de vidro da barra.
private struct ShareButtonGallery: View {
    private let states: [(title: String, symbolName: String, hasWarning: Bool)] = [
        ("Não compartilhado", "person.crop.circle.badge.plus", false),
        ("Compartilhado", "person.2.fill", false),
        ("Com aviso", "person.2.fill", true),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(states, id: \.title) { state in
                VStack(spacing: 8) {
                    Button {
                    } label: {
                        ShareButtonLabel(symbolName: state.symbolName, hasWarning: state.hasWarning)
                    }
                    .buttonStyle(.glass)
                    Text(state.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}
