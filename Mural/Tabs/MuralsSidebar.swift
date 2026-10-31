import MuralKit
import SwiftUI

/// Barra lateral com todos os murais, aberta pelo botão ao lado dos semáforos (o da barra lateral do
/// Safari). Clicar num mural abre a aba dele, ou vai para ela se já estiver aberta.
///
/// Em cima, o título com o botão de novo mural e a busca; no meio, os murais em seções (`SidebarSections`), cada um
/// com a capa em miniatura; embaixo, a contagem e o botão de novo mural de novo (a HIG pede que o que importa não
/// fique só no fundo da barra, que a janela pode esconder).
struct MuralsSidebar: View {
    static let width: CGFloat = 240

    let tabs: MuralTabs

    @State private var entries: [BoardLibraryEntry] = []
    /// Pacotes que não puderam ser lidos; os outros murais continuam na lista.
    @State private var unreadable: [BoardLibraryIssue] = []
    @State private var error: String?
    @State private var query = ""
    @Environment(\.scenePhase) private var scenePhase

    /// Abre o mural numa aba (ou vai para a dele) e deixa o teclado no mural, para ⌘V e Esc agirem nele.
    private func open(_ entry: BoardLibraryEntry) {
        tabs.open(entry.route, title: entry.manifest.name)
        tabs.focusBoard()
    }

    var body: some View {
        let sections = SidebarSections(entries: entries, openRoutes: tabs.tabs.map(\.route), query: query).sections
        // Botões, e não uma `List` com seleção: a lista ficaria com o teclado a cada clique e o ⌘V
        // deixaria de chegar ao mural aberto.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sections) { section in
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, section.id == sections.first?.id ? 0 : 12)
                        .padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(section.entries, id: \.route) { entry in
                        SidebarMuralRow(
                            entry: entry, isSelected: tabs.selected?.route == entry.route, role: tabs.role(for: entry.manifest.cloud),
                            cover: tabs.covers?.images[entry.manifest.id],
                            action: { open(entry) },
                            onDelete: { Task { await tabs.requestDelete(entry.route, name: entry.manifest.name) } },
                            onRemoveFromICloud: { Task { await tabs.requestRemoveFromICloud(entry.route, name: entry.manifest.name) } })
                    }
                }
                if !unreadable.isEmpty {
                    Label(
                        unreadable.count == 1
                            ? "1 mural não pôde ser lido" : "\(unreadable.count) murais não puderam ser lidos",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .help(unreadable.map { "\($0.packageName): \($0.reason)" }.joined(separator: "\n"))
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
        }
        .overlay { emptyState(sections: sections) }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .frame(width: Self.width)
        .background {
            // Mais encorpada que o mural, que deixa passar mais o fundo da janela (`SurfaceFill.boardTint`).
            SidebarFill().ignoresSafeArea()
        }
        .task(id: tabs.libraryRevision) { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh() }
        }
    }

    /// O título, o botão de novo mural e a busca.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Murais")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Novo mural", systemImage: "plus", action: tabs.requestNewBoard)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Novo mural (⌘N)")
                    .accessibilityIdentifier("sidebar-new-board-top")
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Buscar mural", text: $query)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("sidebar-search")
                if !query.isEmpty {
                    Button("Limpar busca", systemImage: "xmark.circle.fill") { query = "" }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("sidebar-search-clear")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.fill.quaternary, in: .rect(cornerRadius: 8))
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    /// A contagem e o botão de novo mural.
    private var footer: some View {
        HStack {
            Button("Novo mural", systemImage: "plus", action: tabs.requestNewBoard)
                .buttonStyle(.borderless)
                .help("Novo mural (⌘N)")
                .accessibilityIdentifier("sidebar-new-board")
            Spacer()
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// "12 murais · 3 no iCloud".
    private var summary: String {
        let count = entries.count
        let cloud = entries.filter { $0.manifest.cloud != nil }.count
        let boards = count == 1 ? "1 mural" : "\(count) murais"
        return cloud == 0 ? boards : "\(boards) · \(cloud) no iCloud"
    }

    @ViewBuilder
    private func emptyState(sections: [SidebarSections.Section]) -> some View {
        if let error {
            ContentUnavailableView(
                "Não foi possível ler os murais", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if entries.isEmpty, unreadable.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("Nenhum mural salvo")
                } icon: {
                    Image(systemName: "rectangle.on.rectangle")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                }
            }
        } else if sections.isEmpty, !query.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private func refresh() async {
        do {
            let report = try await tabs.registry.library.listReport()
            entries = report.entries
            unreadable = report.unreadable
            error = nil
            // As capas em miniatura, na ordem da lista.
            tabs.covers?.request(report.entries)
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
