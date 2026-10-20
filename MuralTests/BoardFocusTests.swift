import MuralKit
import Testing

@testable import Mural

/// O que esmaece e o que fica por cima no mural: pasta em foco, cartão arrastado, pasta de destino e filtro.
@MainActor
struct BoardFocusTests {
    private func card(_ kind: ItemKind) -> BoardItem {
        BoardItem(kind: kind, title: "\(kind)")
    }

    @Test("Sem foco nem filtro, nada esmaece e todos ficam na mesma camada")
    func plainBoardKeepsEveryCardEqual() {
        let focus = BoardFocus()
        for item in [card(.text), card(.sticky), card(.checklist), card(.folder)] {
            #expect(focus.emphasis(for: item) == 1)
            #expect(focus.layer(for: item) == 1)
        }
    }

    @Test("Pasta em foco fica por cima e o resto do mural esmaece")
    func hoveredFolderDimsTheRest() {
        let folder = card(.folder)
        let note = card(.text)
        let focus = BoardFocus(hoveredFolder: folder.id)
        #expect(focus.emphasis(for: folder) == 1)
        #expect(focus.layer(for: folder) == 2)
        #expect(focus.emphasis(for: note) == 0.3)
        #expect(focus.layer(for: note) == 0)
    }

    @Test("Cartão arrastado fica por cima de tudo e nunca esmaece, mesmo fora do filtro")
    func draggedCardStaysOnTopAndSolid() {
        let sticky = card(.sticky)
        let note = card(.text)
        // Controle: sem o arrasto, o filtro de pastas esmaeceria o post-it.
        #expect(BoardFocus(filter: .folders).emphasis(for: sticky) == 0.25)

        let focus = BoardFocus(dragged: sticky.id, filter: .folders)
        #expect(focus.emphasis(for: sticky) == 1)
        #expect(focus.layer(for: sticky) == 4)
        #expect(focus.emphasis(for: note) == 0.25, "o resto do mural continua sob o filtro")
        #expect(focus.layer(for: note) == 0)
    }

    @Test("Pasta arrastada que está em foco continua esmaecendo o resto")
    func draggedFolderInFocusKeepsDimmingTheRest() {
        let folder = card(.folder)
        let note = card(.text)
        let focus = BoardFocus(hoveredFolder: folder.id, dragged: folder.id)
        #expect(focus.emphasis(for: folder) == 1)
        #expect(focus.layer(for: folder) == 4)
        #expect(focus.emphasis(for: note) == 0.3)
        #expect(focus.layer(for: note) == 0)
    }

    @Test("Pasta de destino nunca esmaece e fica abaixo do arrastado e acima da pasta em foco")
    func dropTargetStaysSolidBetweenDraggedAndFocusedFolder() {
        let sticky = card(.sticky)
        let target = card(.folder)
        let focused = card(.folder)
        let note = card(.text)
        // Controles: sem ser destino, a pasta esmaece sob outra pasta em foco e fora do filtro.
        #expect(BoardFocus(hoveredFolder: focused.id).emphasis(for: target) == 0.3)
        #expect(BoardFocus(filter: .tasks).emphasis(for: target) == 0.25)

        let focus = BoardFocus(hoveredFolder: focused.id, dragged: sticky.id, dropTarget: target.id, filter: .tasks)
        #expect(focus.emphasis(for: target) == 1, "o destino nunca esmaece")
        #expect(focus.layer(for: sticky) == 4)
        #expect(focus.layer(for: target) == 3)
        #expect(focus.layer(for: focused) == 2)
        #expect(focus.emphasis(for: note) == 0.3, "o resto do mural continua esmaecido")
        #expect(focus.layer(for: note) == 0)
    }

    @Test("Com filtro, os destacados ficam à frente dos esmaecidos")
    func filterPutsHighlightedCardsInFront() {
        let list = card(.checklist)
        let note = card(.text)
        let focus = BoardFocus(filter: .tasks)
        #expect(focus.emphasis(for: list) == 1)
        #expect(focus.layer(for: list) == 1)
        #expect(focus.emphasis(for: note) == 0.25)
        #expect(focus.layer(for: note) == 0)
    }
}
