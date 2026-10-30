import AppKit
import Testing

@testable import Mural

/// O ícone da barra de menus: o normal e o de quando uma edição espera para ser colada.
@MainActor
struct MenuBarIconTests {
    @Test("Sem edição pendente, o ícone, a descrição e a dica são os de sempre")
    func normalIcon() {
        #expect(MenuBarIcon.symbolName(isEditPending: false) == "rectangle.on.rectangle")
        #expect(MenuBarIcon.accessibilityDescription(isEditPending: false) == "Mural")
        #expect(MenuBarIcon.toolTip(isEditPending: false) == "Mural")
    }

    @Test("Com uma edição pendente, o ícone vira o lápis e a descrição e a dica dizem o porquê")
    func pendingIcon() {
        #expect(MenuBarIcon.symbolName(isEditPending: true) == "square.and.pencil")
        #expect(MenuBarIcon.accessibilityDescription(isEditPending: true) == "Mural — edição esperando para colar")
        #expect(MenuBarIcon.toolTip(isEditPending: true) == "Mural: há uma edição esperando para ser colada")
    }

    @Test("Os dois símbolos existem no sistema")
    func symbolsExist() {
        for pending in [false, true] {
            let name = MenuBarIcon.symbolName(isEditPending: pending)
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
        }
    }
}
