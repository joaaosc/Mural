import MuralKit
import SwiftUI

/// Uma linha da barra lateral: a capa em miniatura, o nome do mural, quando foi atualizado e, se for do iCloud, um
/// selo discreto. O fundo fica destacado quando ele é a aba ativa.
struct SidebarMuralRow: View {
    let entry: BoardLibraryEntry
    let isSelected: Bool
    /// O papel da pessoa no mural do iCloud (`MuralTabs.role(for:)`): `nil` num mural só deste Mac.
    let role: BoardCloudInfo.Database?
    /// A capa já desenhada; `nil` enquanto não há.
    var cover: CGImage?
    var action: () -> Void
    var onDelete: () -> Void
    var onRemoveFromICloud: () -> Void

    /// Tamanho da miniatura: a proporção da capa (`BoardCoverView.size`, 8:5).
    static let coverSize = CGSize(width: 40, height: 25)

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.manifest.name)
                        .lineLimit(1)
                    Text(entry.manifest.updatedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                badge
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // O rótulo é só o nome (os testes de interface e o VoiceOver acham o mural por ele); a data vai no valor.
        .accessibilityLabel(entry.manifest.name)
        .accessibilityValue(entry.manifest.updatedAt.formatted(.relative(presentation: .named)))
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

    /// A capa, ou um quadro na cor do mural com o símbolo do tipo enquanto ela não chega.
    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if let cover {
                Image(decorative: cover, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Theme.canvas
                    .overlay {
                        Image(systemName: entry.route.isDraft ? "doc.badge.clock" : "rectangle.on.rectangle")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
            }
        }
        .frame(width: Self.coverSize.width, height: Self.coverSize.height)
        .clipShape(.rect(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.quaternary))
        .accessibilityHidden(true)
    }

    /// Só com significado: compartilhado por outra pessoa ou guardado no iCloud da pessoa.
    @ViewBuilder
    private var badge: some View {
        switch role {
        case .shared:
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
                .help("Compartilhado pelo iCloud")
                .accessibilityLabel("Compartilhado")
        case .private:
            Image(systemName: "icloud")
                .foregroundStyle(.secondary)
                .help("No iCloud")
                .accessibilityLabel("No iCloud")
        case nil:
            EmptyView()
        }
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

#if DEBUG
#Preview("Linhas da barra lateral") {
    let now = Date.now
    func entry(_ name: String, hoursAgo: Double, cloud: BoardCloudInfo? = nil, draft: Bool = false) -> BoardLibraryEntry {
        let id = BoardID()
        return BoardLibraryEntry(
            manifest: BoardManifest(id: id, name: name, updatedAt: now.addingTimeInterval(-hoursAgo * 3_600), cloud: cloud),
            route: draft ? .welcomeDraft(id) : .saved(id))
    }
    return VStack(alignment: .leading, spacing: 2) {
        SidebarMuralRow(
            entry: entry("Viagem para Lisboa", hoursAgo: 2), isSelected: true, role: nil, action: {}, onDelete: {},
            onRemoveFromICloud: {})
        SidebarMuralRow(
            entry: entry("Casa nova", hoursAgo: 30), isSelected: false, role: .shared, action: {}, onDelete: {},
            onRemoveFromICloud: {})
        SidebarMuralRow(
            entry: entry("Receitas da família com um nome bem comprido", hoursAgo: 200), isSelected: false, role: .private,
            action: {}, onDelete: {}, onRemoveFromICloud: {})
        SidebarMuralRow(
            entry: entry("Rascunho de exemplo", hoursAgo: 0.1, draft: true), isSelected: false, role: nil, action: {},
            onDelete: {}, onRemoveFromICloud: {})
    }
    .padding(10)
    .frame(width: MuralsSidebar.width)
    .background { SidebarFill() }
}
#endif
