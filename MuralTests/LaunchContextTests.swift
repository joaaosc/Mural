import AppKit
import Testing

@testable import Mural

/// O Mural aberto pelo início de sessão fica só na barra de menus; aberto de outro jeito, abre a janela. O que distingue um
/// do outro é o evento de abertura do sistema.
@Suite("Como o app foi aberto")
struct LaunchContextTests {
    /// Um evento de Apple como o do sistema, sem alvo: o que importa aqui são a classe, o código e o parâmetro.
    private func event(
        eventClass: AEEventClass = AEEventClass(kCoreEventClass), eventID: AEEventID = AEEventID(kAEOpenApplication),
        propData: AEKeyword? = nil
    ) -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: eventClass, eventID: eventID, targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let propData {
            event.setParam(NSAppleEventDescriptor(enumCode: OSType(propData)), forKeyword: AEKeyword(keyAEPropData))
        }
        return event
    }

    private let loginItem = AEKeyword(keyAELaunchedAsLogInItem)

    @Test("Abertura com o parâmetro de item de início de sessão é início de sessão")
    func openApplicationWithLoginItemMarkerIsALoginLaunch() {
        #expect(LaunchContext.isLoginItemLaunch(event(propData: loginItem)))
    }

    @Test("Abertura sem o parâmetro é uma abertura comum (Finder, Spotlight, Dock)")
    func openApplicationWithoutMarkerIsAnOrdinaryLaunch() {
        #expect(!LaunchContext.isLoginItemLaunch(event()))
    }

    @Test("Abertura marcada de outro jeito (item de serviço) não é início de sessão")
    func otherMarkersAreNotLoginLaunches() {
        #expect(!LaunchContext.isLoginItemLaunch(event(propData: AEKeyword(keyAELaunchedAsServiceItem))))
    }

    @Test("Outro evento, mesmo com o parâmetro, não é início de sessão")
    func otherEventsAreNotLoginLaunches() {
        let reopen = event(eventID: AEEventID(kAEReopenApplication), propData: loginItem)
        #expect(!LaunchContext.isLoginItemLaunch(reopen))

        let otherClass = event(eventClass: AEEventClass(kAECoreSuite), propData: loginItem)
        #expect(!LaunchContext.isLoginItemLaunch(otherClass))
    }

    @Test("Sem evento nenhum, é uma abertura comum")
    func noEventIsAnOrdinaryLaunch() {
        #expect(!LaunchContext.isLoginItemLaunch(nil))
    }
}
