import MuralKit
import SwiftUI

/// Barra lateral com todos os murais, aberta pelo botão ao lado dos semáforos (o da barra lateral do
/// Safari). Clicar num mural abre a aba dele, ou vai para ela se já estiver aberta.
struct MuralsSidebar: View {
    static let width: CGFloat = 240

    let tabs: MuralTabs
    var playback: MusicPlayback = .shared
    var dockStore: NowPlayingDockStore = .shared

    @State private var entries: [BoardLibraryEntry] = []
    /// Pacotes que não puderam ser lidos; os outros murais continuam na lista.
    @State private var unreadable: [BoardLibraryIssue] = []
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    /// Abre o mural numa aba (ou vai para a dele) e deixa o teclado no mural, para ⌘V e Esc agirem nele.
    private func open(_ entry: BoardLibraryEntry) {
        tabs.open(entry.route, title: entry.manifest.name)
        tabs.focusBoard()
    }

    var body: some View {
        // Botões, e não uma `List` com seleção: a lista ficaria com o teclado a cada clique e o ⌘V
        // deixaria de chegar ao mural aberto.
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                Text("Murais")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
                ForEach(entries, id: \.route) { entry in
                    SidebarMuralRow(
                        entry: entry, isSelected: tabs.selected?.route == entry.route, role: tabs.role(for: entry.manifest.cloud),
                        action: { open(entry) },
                        onDelete: { Task { await tabs.requestDelete(entry.route, name: entry.manifest.name) } },
                        onRemoveFromICloud: { Task { await tabs.requestRemoveFromICloud(entry.route, name: entry.manifest.name) } })
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
            .padding(.top, 8)
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
            VStack(spacing: 0) {
                SidebarNowPlaying(tabs: tabs, playback: playback, dockStore: dockStore)
                Button("Novo mural", systemImage: "plus", action: tabs.requestNewBoard)
                    .buttonStyle(.borderless)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .help("Novo mural (⌘N)")
                    .accessibilityIdentifier("sidebar-new-board")
            }
        }
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

/// A seção "Tocando agora" com os divisores: aparece quando o miniplayer foi levado para a barra lateral e há música; senão,
/// não desenha nada. Numa view à parte, para que só ela releia o tocador a cada faixa, e não a lista de murais.
private struct SidebarNowPlaying: View {
    let tabs: MuralTabs
    let playback: MusicPlayback
    let dockStore: NowPlayingDockStore

    var body: some View {
        if dockStore.isInSidebar, let summary = playback.summary(in: tabs) {
            Divider()
            NowPlayingSidebarSection(
                summary: summary,
                actions: playback.nowPlayingActions(
                    openSource: { tabs.showBoard(summary.route, title: summary.boardTitle) }),
                returnToMiniPlayer: { dockStore.isInSidebar = false })
            Divider()
        }
    }
}

/// Uma linha da barra lateral: o nome do mural, com o fundo destacado quando ele é a aba ativa.
private struct SidebarMuralRow: View {
    let entry: BoardLibraryEntry
    let isSelected: Bool
    /// O papel da pessoa no mural do iCloud (`MuralTabs.role(for:)`): `nil` num mural só deste Mac.
    let role: BoardCloudInfo.Database?
    var action: () -> Void
    var onDelete: () -> Void
    var onRemoveFromICloud: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(entry.manifest.name, systemImage: entry.route.isDraft ? "doc.badge.clock" : "rectangle.on.rectangle")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(background, in: .rect(cornerRadius: 8))
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Abrir", action: action)
            Divider()
            if role == .private {
                Button("Tirar do iCloud…", action: onRemoveFromICloud)
            }
            Button(deleteTitle, role: .destructive, action: onDelete)
                .accessibilityIdentifier("sidebar-delete-board")
        }
        .accessibilityIdentifier(
            entry.route.isDraft
                ? "welcome-draft-entry" : "saved-board-entry-\(entry.manifest.id.rawValue.uuidString)"
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var deleteTitle: String {
        entry.route.isDraft ? "Descartar Rascunho…" : BoardDeletionRequest.menuTitle(role: role)
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.fill.secondary) }
        if isHovering { return AnyShapeStyle(.fill.quaternary) }
        return AnyShapeStyle(.clear)
    }
}
