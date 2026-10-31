import Foundation
import MuralKit
import Testing

@testable import Mural

@Suite("Seções da barra lateral")
@MainActor
struct SidebarSectionsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func entry(_ name: String, daysAgo: Double = 0) -> BoardLibraryEntry {
        let id = BoardID()
        return BoardLibraryEntry(
            manifest: BoardManifest(id: id, name: name, updatedAt: now.addingTimeInterval(-daysAgo * 86_400)),
            route: .saved(id))
    }

    private func names(_ section: SidebarSections.Section) -> [String] { section.entries.map(\.manifest.name) }

    @Test("Poucos murais: uma lista só, em ordem alfabética")
    func fewBoardsStayInOneSection() {
        let sections = SidebarSections(entries: [entry("Viagem"), entry("Casa"), entry("Ideias")], openRoutes: [], query: "").sections
        #expect(sections.map(\.id) == ["all"])
        #expect(names(sections[0]) == ["Casa", "Ideias", "Viagem"])
    }

    @Test("Os abertos nesta janela vêm primeiro, na ordem das abas, e não se repetem")
    func openBoardsComeFirst() {
        let casa = entry("Casa")
        let viagem = entry("Viagem")
        let sections = SidebarSections(entries: [casa, viagem, entry("Ideias")], openRoutes: [viagem.route, casa.route], query: "")
            .sections
        #expect(sections.map(\.id) == ["open", "all"])
        #expect(names(sections[0]) == ["Viagem", "Casa"])
        #expect(names(sections[1]) == ["Ideias"])
    }

    @Test("Com muitos murais, os cinco mais recentes ganham a própria seção")
    func recentsAppearWithManyBoards() {
        let entries = (0..<8).map { entry("Mural \($0)", daysAgo: Double($0)) }
        let sections = SidebarSections(entries: entries.shuffled(), openRoutes: [], query: "").sections
        #expect(sections.map(\.id) == ["recent", "all"])
        #expect(names(sections[0]) == ["Mural 0", "Mural 1", "Mural 2", "Mural 3", "Mural 4"])
        #expect(names(sections[1]) == ["Mural 5", "Mural 6", "Mural 7"])
    }

    @Test("A busca ignora maiúsculas e acentos e devolve uma seção só")
    func searchFiltersByName() {
        let entries = [entry("Férias 2026"), entry("Casa"), entry("ferias antigas")]
        let sections = SidebarSections(entries: entries, openRoutes: [entries[1].route], query: "  ferias ").sections
        #expect(sections.map(\.id) == ["results"])
        #expect(names(sections[0]) == ["Férias 2026", "ferias antigas"])
    }

    @Test("Busca sem resultado não tem seção nenhuma")
    func searchWithoutMatches() {
        #expect(SidebarSections(entries: [entry("Casa")], openRoutes: [], query: "xyz").sections.isEmpty)
    }

    @Test("Sem murais, nada")
    func empty() {
        #expect(SidebarSections(entries: [], openRoutes: [], query: "").sections.isEmpty)
    }
}
