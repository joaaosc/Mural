import MuralKit
import SwiftUI

/// Seletor "Mural: nome" da barra da janela. Lista os murais da biblioteca e o rascunho
/// de exemplo; escolher um mural já aberto traz a janela dele para a frente (uma janela
/// por mural) e escolher outro abre a sessão restaurada dele.
struct BoardSwitcherMenu: View {
    let currentName: String
    let currentRoute: BoardRoute
    let library: BoardLibrary
    var onNewBoard: () -> Void

    @State private var entries: [BoardLibraryEntry] = []
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Menu {
            ForEach(entries, id: \.route) { entry in
                Toggle(
                    entry.manifest.name,
                    isOn: Binding(
                        get: { entry.route == currentRoute },
                        set: { _ in openWindow(value: entry.route) }))
            }
            if !entries.isEmpty { Divider() }
            Button("Novo Mural…", action: onNewBoard)
            Button("Mostrar Todos os Murais") { openWindow(value: BoardRoute.library) }
        } label: {
            Text("Mural: \(currentName)")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .menuIndicator(.visible)
        .fixedSize()
        .help("Trocar de mural")
        .accessibilityLabel("Mural: \(currentName)")
        .accessibilityHint("Abre a lista de murais")
        .task(id: currentName) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
    }

    private func refresh() async {
        entries = (try? await library.list()) ?? entries
    }
}

#Preview("Na barra da janela") {
    NavigationStack {
        Theme.canvas
            .frame(width: 760, height: 220)
            .navigationTitle("Viagem ao Japão")
            .navigationSubtitle("Hotel › Quarto")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    BoardSwitcherMenu(
                        currentName: "Viagem ao Japão",
                        currentRoute: .library,
                        library: BoardLibrary(
                            rootDirectory: FileManager.default.temporaryDirectory
                                .appendingPathComponent("MuralPreviewLibrary", isDirectory: true)),
                        onNewBoard: {})
                }
            }
    }
}
