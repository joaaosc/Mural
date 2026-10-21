import MuralKit
import SwiftUI

/// Um tipo de cartão no popup de colar. O sugerido é o botão padrão (Return).
struct PasteChoiceButton: View {
    let kind: ItemKind
    let isSuggested: Bool
    let action: () -> Void

    var body: some View {
        if isSuggested {
            Button(kind.creationTitle, systemImage: kind.creationSymbol, action: action)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button(kind.creationTitle, systemImage: kind.creationSymbol, action: action)
                .buttonStyle(.bordered)
        }
    }
}
