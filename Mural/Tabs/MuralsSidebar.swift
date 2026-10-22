import MuralKit
import SwiftUI

/// Barra lateral com todos os murais, aberta pelo botão ao lado dos semáforos (o da barra lateral do
/// Safari). Clicar num mural abre a aba dele, ou vai para ela se já estiver aberta.
struct MuralsSidebar: View {
    let tabs: MuralTabs

    @State private var entries: [BoardLibraryEntry] = []
    /// Pacotes que não puderam ser lidos; os outros murais continuam na lista.
    @State private var unreadable: [BoardLibraryIssue] = []
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    private var selection: Binding<BoardRoute?> {
        Binding(
            get: { tabs.selected?.route },
            set: { route in
                guard let route, let entry = entries.first(where: { $0.route == route }) else { return }
                tabs.open(route, title: entry.manifest.name)
            })
    }

    var body: some View {
        List(selection: selection) {
            Section("Murais") {
                ForEach(entries, id: \.route) { entry in
                    Label(entry.manifest.name, systemImage: entry.route.isDraft ? "doc.badge.clock" : "rectangle.on.rectangle")
                        .tag(entry.route)
                        .accessibilityIdentifier(
                            entry.route.isDraft
                                ? "welcome-draft-entry"
                                : "saved-board-entry-\(entry.manifest.id.rawValue.uuidString)")
                }
            }
            if !unreadable.isEmpty {
                Section {
                    Label(
                        unreadable.count == 1
                            ? "1 mural não pôde ser lido" : "\(unreadable.count) murais não puderam ser lidos",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                    .help(unreadable.map { "\($0.packageName): \($0.reason)" }.joined(separator: "\n"))
                }
            }
        }
        .overlay {
            if entries.isEmpty, unreadable.isEmpty, error == nil {
                ContentUnavailableView("Nenhum mural salvo", systemImage: "rectangle.on.rectangle")
            } else if let error {
                ContentUnavailableView(
                    "Não foi possível ler os murais", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button("Novo mural", systemImage: "plus") { tabs.requestNewBoard() }
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .help("Novo mural (⌘N)")
                .accessibilityIdentifier("sidebar-new-board")
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        .task(id: tabs.libraryRevision) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
    }

    private func refresh() async {
        do {
            let report = try await tabs.registry.library.listReport()
            entries = report.entries
            unreadable = report.unreadable
            error = nil
        } catch let loadError {
            error = loadError.localizedDescription
        }
        await tabs.refreshDraftAvailability()
    }
}

extension BoardRoute {
    /// O rascunho de exemplo (aparece com outro ícone na lista).
    var isDraft: Bool {
        if case .welcomeDraft = self { return true }
        return false
    }
}
