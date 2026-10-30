import MuralKit
import SwiftUI

/// A lista "Colar como": uma linha por jeito de colar o texto, com o escolhido em destaque; as que não valem ficam desligadas, com a
/// razão no lugar do resumo.
struct PasteKindList: View {
    let suggestion: PasteKindSuggestion
    let selectedKind: PasteKind
    let boardName: String
    let choose: @MainActor (PasteKind) -> Void

    @Namespace private var selectionPill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Colar como")
                .font(.headline)
                .padding(.horizontal, 10)
            VStack(spacing: 2) {
                ForEach(suggestion.options, id: \.self) { kind in
                    let reason = suggestion.unavailable[kind]
                    let title = PasteKindWording.title(of: kind)
                    PanelActionRow(
                        symbolName: PasteKindWording.symbol(of: kind),
                        title: title,
                        summary: PasteKindWording.summary(unavailable: reason, board: boardName),
                        isSelected: reason == nil && kind == selectedKind,
                        namespace: selectionPill,
                        help: reason ?? "\(title) em \(boardName)",
                        accessibilityLabel: reason.map { "\(title), indisponível: \($0)" } ?? "\(title) em \(boardName)",
                        accessibilityHint: reason == nil ? "Escolhe como o texto vira cartão." : "",
                        alwaysShowsSummary: reason != nil,
                        action: { choose(kind) }
                    )
                    .disabled(reason != nil)
                    .opacity(reason == nil ? 1 : 0.55)
                    .accessibilityIdentifier("paste-destination-kind-\(identifier(of: kind))")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paste-destination-kinds")
    }

    private func identifier(of kind: PasteKind) -> String {
        switch kind {
        case .sticky: "sticky"
        case .text: "text"
        case .checklist: "checklist"
        case .links: "links"
        }
    }
}
