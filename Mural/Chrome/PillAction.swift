import SwiftUI

/// Uma ação da pílula do detalhe.
struct PillAction: Identifiable {
    let title: String
    let symbol: String
    var role: ButtonRole?
    var shortcut: KeyboardShortcut?
    let perform: () -> Void

    var id: String { title }
}
