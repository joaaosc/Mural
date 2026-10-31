import Foundation
import MuralKit

/// Como a barra lateral agrupa os murais: com uma busca, só os que casam com o texto; sem busca, os abertos nesta
/// janela, os mais recentes e, por fim, os demais em ordem alfabética. Cada mural aparece uma vez só.
///
/// Fica fora da view para a regra poder ser testada.
struct SidebarSections: Equatable {
    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        let entries: [BoardLibraryEntry]
    }

    /// Quantos murais entram em "Recentes".
    static let recentLimit = 5

    let sections: [Section]

    /// - Parameters:
    ///   - entries: os murais da biblioteca, na ordem em que ela os lista.
    ///   - openRoutes: as rotas das abas abertas, na ordem das abas.
    ///   - query: o texto da busca; em branco, não há busca.
    init(entries: [BoardLibraryEntry], openRoutes: [BoardRoute], query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let matches = entries.filter { $0.manifest.name.localizedStandardContains(trimmed) }
            sections = matches.isEmpty ? [] : [Section(id: "results", title: "Resultados", entries: Self.alphabetical(matches))]
            return
        }
        var remaining = entries
        var sections: [Section] = []

        let open = openRoutes.compactMap { route in remaining.first { $0.route == route } }
        if !open.isEmpty {
            sections.append(Section(id: "open", title: "Nesta janela", entries: open))
            remaining.removeAll { entry in open.contains { $0.route == entry.route } }
        }

        let recent = Array(remaining.sorted { $0.manifest.updatedAt > $1.manifest.updatedAt }.prefix(Self.recentLimit))
        // Só vale a pena separar os recentes quando ainda sobra algo para a lista geral.
        if remaining.count > Self.recentLimit, !recent.isEmpty {
            sections.append(Section(id: "recent", title: "Recentes", entries: recent))
            remaining.removeAll { entry in recent.contains { $0.route == entry.route } }
        }

        if !remaining.isEmpty {
            sections.append(Section(id: "all", title: "Murais", entries: Self.alphabetical(remaining)))
        }
        self.sections = sections
    }

    private static func alphabetical(_ entries: [BoardLibraryEntry]) -> [BoardLibraryEntry] {
        entries.sorted { $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending }
    }
}
