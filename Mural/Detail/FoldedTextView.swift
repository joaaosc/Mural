import MuralKit
import StretchText
import StretchTextUI
import SwiftUI

/// Texto dobrado pelo StretchText numa tela de leitura. Os parágrafos abrem e
/// fecham no lugar, e os abertos ficam guardados na sessão para a próxima vez.
///
/// Os parágrafos guardados são abertos já no estado inicial, antes do primeiro
/// layout, para que a restauração da rolagem encontre a altura certa.
struct FoldedTextView: View {
    let itemID: UUID
    let result: FoldResult
    let session: BoardWindowSession?

    @State private var state: StretchState

    init(itemID: UUID, result: FoldResult, session: BoardWindowSession?) {
        self.itemID = itemID
        self.result = result
        self.session = session
        _state = State(initialValue: Self.restoredState(itemID: itemID, result: result, session: session))
    }

    var body: some View {
        StretchMarkdownView(result: result, state: $state)
            .onChange(of: result) { old, new in
                adopt(new, replacing: old)
            }
            .onChange(of: state.openIDs) { _, ids in
                record(ids)
            }
    }

    /// Frases curtas novas para o mesmo texto mantêm os abertos. Texto novo reabre só o que a sessão
    /// guarda para ele (como depois de marcar uma tarefa); numa edição comum a memória é do texto velho
    /// e tudo volta dobrado.
    private func adopt(_ new: FoldResult, replacing old: FoldResult) {
        if new.segmentation.source == old.segmentation.source {
            state.replaceDocument(new.document)
        } else {
            state = Self.restoredState(itemID: itemID, result: new, session: session)
        }
    }

    private func record(_ ids: Set<StretchID>) {
        session?.recordOpenStretches(ids, for: itemID, source: result.segmentation.source)
    }

    private static func restoredState(itemID: UUID, result: FoldResult, session: BoardWindowSession?) -> StretchState {
        var state = StretchState(document: result.document)
        for id in session?.openStretchIDs(for: itemID, source: result.segmentation.source) ?? [] {
            state.toggle(id)
        }
        return state
    }
}
