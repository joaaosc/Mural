import MuralSync
import SwiftUI

/// O que o indicador mostra: o símbolo, o texto (rótulo de acessibilidade e dica) e se é um problema. Função pura do aviso
/// do mural, sem interface.
nonisolated struct SyncStatusDisplay: Equatable {
    var symbolName: String
    var text: String
    /// `true` para o que a pessoa precisa saber (o símbolo ganha cor); o resto é discreto.
    var isWarning: Bool

    /// - Parameter issue: o aviso do mural em `CloudSyncController.issues`; `nil` quando nada impede de sincronizar.
    init(issue: SyncIssue?) {
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
                "exclamationmark.icloud", "Este mural pede uma versão mais nova do Mural. Atualize o app para sincronizar", isWarning: true)
        case .localSaveFailed:
            self.init("exclamationmark.icloud", "Não foi possível gravar neste Mac o que veio do iCloud", isWarning: true)
        case .awaitingFirstFetch:
            self.init("icloud.and.arrow.down", "Baixando do iCloud…", isWarning: false)
        case .other:
            self.init("exclamationmark.icloud", "Não foi possível sincronizar com o iCloud", isWarning: true)
        }
    }

    private init(_ symbolName: String, _ text: String, isWarning: Bool) {
        self.symbolName = symbolName
        self.text = text
        self.isWarning = isWarning
    }
}

/// O estado da sincronização de um mural que está no iCloud, discreto na barra da janela. Só o ícone; o texto vai na dica e na
/// acessibilidade. O controlador ainda não expõe "enviando", então só há "sincronizado" e os avisos.
struct SyncStatusIndicator: View {
    /// A largura que o ícone ocupa na barra da janela, para a faixa de abas ceder o lugar.
    static let toolbarWidth: CGFloat = 48

    let issue: SyncIssue?

    var body: some View {
        let display = SyncStatusDisplay(issue: issue)
        Image(systemName: display.symbolName)
            .foregroundStyle(display.isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            .help(display.text)
            .accessibilityLabel(display.text)
            .accessibilityIdentifier("sync-status-indicator")
    }
}

#Preview("Estados", traits: .fixedLayout(width: 300, height: 240)) {
    SyncStatusIndicatorGallery()
}

#Preview("Estados (escuro)", traits: .fixedLayout(width: 300, height: 240)) {
    SyncStatusIndicatorGallery()
        .preferredColorScheme(.dark)
}

/// Os estados lado a lado, com o texto, para conferir símbolo e cor no claro e no escuro.
private struct SyncStatusIndicatorGallery: View {
    private let issues: [SyncIssue?] = [
        nil, .awaitingFirstFetch, .readOnly, .quotaExceeded, .recordTooLarge(UUID()), .needsNewerApp, .localSaveFailed, .other("x"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                HStack(spacing: 8) {
                    SyncStatusIndicator(issue: issue)
                    Text(SyncStatusDisplay(issue: issue).text)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(.background)
    }
}
