import MuralSync
import SwiftUI

/// O que o botão Compartilhar e o popover dizem do estado do mural no iCloud: o símbolo, o texto (rótulo de acessibilidade e linha de
/// estado) e se é um problema. Função pura do estado do mural, sem interface.
nonisolated struct SyncStatusDisplay: Equatable {
    var symbolName: String
    var text: String
    /// `true` para o que a pessoa precisa saber (o símbolo ganha cor e o botão ganha o selo); o resto é discreto.
    var isWarning: Bool

    /// A ordem de prioridade: sem conta, enviando, só neste Mac, o aviso do mural e, sem nada disso, sincronizado.
    /// - Parameters:
    ///   - issue: o aviso do mural em `CloudSyncController.issues`; `nil` quando nada impede de sincronizar.
    ///   - isInCloud: o mural tem `cloud` no manifesto (é do dono no iCloud, ou veio de um convite).
    ///   - isSending: o controlador está enviando o mural agora (`CloudSyncController.sendingBoards`).
    ///   - accountAvailable: há conta do iCloud neste Mac (`CloudSyncController.accountAvailable`).
    init(issue: SyncIssue?, isInCloud: Bool, isSending: Bool, accountAvailable: Bool) {
        if !accountAvailable {
            // Só é problema para quem tem mural no iCloud parado; quem só usa o Mac não precisa de selo de aviso.
            self.init("icloud.slash", "Entre no iCloud nos Ajustes do Sistema para compartilhar", isWarning: isInCloud)
        } else if isSending {
            self.init("icloud.and.arrow.up", "Enviando ao iCloud…", isWarning: false)
        } else if !isInCloud {
            self.init("icloud", "Só neste Mac", isWarning: false)
        } else {
            switch issue {
            case nil:
                self.init("checkmark.icloud", "Sincronizado com o iCloud", isWarning: false)
            case .quotaExceeded:
                self.init("exclamationmark.icloud", "Sem espaço no iCloud do dono do mural", isWarning: true)
            case .readOnly:
                self.init("icloud", "Você só pode ver este mural", isWarning: false)
            case .recordTooLarge:
                self.init("exclamationmark.icloud", "Um cartão é grande demais para o iCloud e não será enviado", isWarning: true)
            case .needsNewerApp:
                self.init(
                    "exclamationmark.icloud", "Este mural pede uma versão mais nova do Mural. Atualize o app para sincronizar",
                    isWarning: true)
            case .localSaveFailed:
                self.init("exclamationmark.icloud", "Não foi possível gravar neste Mac o que veio do iCloud", isWarning: true)
            case .awaitingFirstFetch:
                self.init("icloud.and.arrow.down", "Baixando do iCloud…", isWarning: false)
            case .other:
                self.init("exclamationmark.icloud", "Não foi possível sincronizar com o iCloud", isWarning: true)
            }
        }
    }

    private init(_ symbolName: String, _ text: String, isWarning: Bool) {
        self.symbolName = symbolName
        self.text = text
        self.isWarning = isWarning
    }
}

#Preview("Estados", traits: .fixedLayout(width: 380, height: 330)) {
    SyncStatusDisplayGallery()
}

#Preview("Estados (escuro)", traits: .fixedLayout(width: 380, height: 330)) {
    SyncStatusDisplayGallery()
        .preferredColorScheme(.dark)
}

/// Os estados lado a lado, com o texto, para conferir símbolo e cor no claro e no escuro.
private struct SyncStatusDisplayGallery: View {
    private let displays: [SyncStatusDisplay] = [
        SyncStatusDisplay(issue: nil, isInCloud: true, isSending: false, accountAvailable: false),
        SyncStatusDisplay(issue: nil, isInCloud: true, isSending: true, accountAvailable: true),
        SyncStatusDisplay(issue: nil, isInCloud: false, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: nil, isInCloud: true, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: .awaitingFirstFetch, isInCloud: true, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: .readOnly, isInCloud: true, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: .quotaExceeded, isInCloud: true, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: .recordTooLarge(UUID()), isInCloud: true, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: .needsNewerApp, isInCloud: true, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: .localSaveFailed, isInCloud: true, isSending: false, accountAvailable: true),
        SyncStatusDisplay(issue: .other("x"), isInCloud: true, isSending: false, accountAvailable: true),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(displays.enumerated()), id: \.offset) { _, display in
                Label(display.text, systemImage: display.symbolName)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(display.isWarning ? Color.orange : Color.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.background)
    }
}
