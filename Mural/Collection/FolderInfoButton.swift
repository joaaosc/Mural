import MuralKit
import SwiftUI

/// Botão ⓘ que abre os detalhes da pasta num popover (também por ⌘I).
struct FolderInfoButton: View {
    let folder: BoardItem
    let children: [BoardItem]

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Informações da pasta", systemImage: "info")
                .labelStyle(.iconOnly)
                .frame(width: 22, height: 22)
                .contentShape(.circle)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .keyboardShortcut("i")
        .help("Informações da pasta (⌘I)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            FolderInfoView(folder: folder, children: children)
        }
    }
}
