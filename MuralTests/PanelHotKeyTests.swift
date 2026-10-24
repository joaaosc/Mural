import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Mural

/// Um registro de atalho que não fala com o sistema: guarda o que foi pedido e responde o que o teste mandar.
@MainActor
private final class FakeRegistrar: HotKeyRegistrar {
    var nextStatus: OSStatus = noErr
    private(set) var registered: PanelHotKey?
    private(set) var registrations: [PanelHotKey] = []

    func register(_ hotKey: PanelHotKey) -> OSStatus {
        registrations.append(hotKey)
        registered = nextStatus == noErr ? hotKey : nil
        return nextStatus
    }

    func unregister() {
        registered = nil
    }
}

/// O atalho global que abre o painel da barra de menus: a combinação, o que fica guardado e quando ele vale.
@Suite("Atalho do painel")
@MainActor
struct PanelHotKeyTests {
    // MARK: Combinação

    @Test("O padrão é ⌘ com a tecla do acento grave")
    func standardIsCommandGrave() {
        #expect(PanelHotKey.standard.keyCode == UInt32(kVK_ANSI_Grave))
        #expect(PanelHotKey.standard.flags == .command)
        #expect(PanelHotKey.standard.carbonModifiers == UInt32(cmdKey))
        #expect(PanelHotKey.standard.displayString.hasPrefix("⌘"))
    }

    @Test("Precisa de ⌘ ou ⌃; só ⇧ ou ⌥, ou só um modificador, não é atalho")
    func requiresCommandOrControl() {
        #expect(PanelHotKey(keyCode: UInt16(kVK_ANSI_A), modifiers: [.shift]) == nil)
        #expect(PanelHotKey(keyCode: UInt16(kVK_ANSI_E), modifiers: [.option]) == nil)
        #expect(PanelHotKey(keyCode: UInt16(kVK_ANSI_A), modifiers: []) == nil)
        #expect(PanelHotKey(keyCode: UInt16(kVK_Command), modifiers: [.command]) == nil)
        #expect(PanelHotKey(keyCode: UInt16(kVK_Space), modifiers: [.control, .option]) != nil)
    }

    @Test("Caps Lock e Fn não entram, e os símbolos seguem a ordem do macOS")
    func ignoresOtherModifiersAndOrdersSymbols() throws {
        let hotKey = try #require(
            PanelHotKey(keyCode: UInt16(kVK_Space), modifiers: [.command, .shift, .option, .control, .capsLock, .function]))
        #expect(hotKey.flags == [.command, .shift, .option, .control])
        #expect(hotKey.modifierSymbols == "⌃⌥⇧⌘")
        #expect(hotKey.displayString == "⌃⌥⇧⌘Espaço")
        #expect(hotKey.carbonModifiers == UInt32(cmdKey | shiftKey | optionKey | controlKey))
    }

    @Test("Teclas sem caractere têm nome fixo")
    func namedKeys() {
        #expect(PanelHotKey.keyName(for: UInt32(kVK_Return)) == "↩")
        #expect(PanelHotKey.keyName(for: UInt32(kVK_LeftArrow)) == "←")
        #expect(PanelHotKey.keyName(for: UInt32(kVK_F5)) == "F5")
    }

    // MARK: Guardado e registro

    @Test("Sem nada guardado vale o padrão, registrado só quando esta cópia é a dona do ícone")
    func standardRegistersOnlyForTheOwner() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let registrar = FakeRegistrar()
        let center = PanelHotKeyCenter(preferences: preferences, registrar: registrar, isEnabled: true)
        center.start {}

        #expect(center.hotKey == .standard)
        #expect(!center.isActive, "antes de ser a dona do ícone, nada é registrado")
        #expect(registrar.registered == nil)

        center.setOwner(true)
        #expect(center.isActive)
        #expect(registrar.registered == .standard)

        center.setOwner(false)
        #expect(!center.isActive)
        #expect(registrar.registered == nil, "a cópia que perdeu o ícone solta o atalho")
    }

    @Test("Trocar, tirar e voltar ao padrão ficam guardados para a próxima abertura")
    func choicesSurviveANewCenter() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let center = PanelHotKeyCenter(preferences: preferences, registrar: FakeRegistrar(), isEnabled: true)
        let custom = try #require(PanelHotKey(keyCode: UInt16(kVK_ANSI_M), modifiers: [.command, .option]))

        center.update(to: custom)
        #expect(PanelHotKeyCenter(preferences: preferences, isEnabled: false).hotKey == custom)

        center.remove()
        #expect(center.hotKey == nil)
        #expect(PanelHotKeyCenter(preferences: preferences, isEnabled: false).hotKey == nil, "tirado, não volta sozinho")

        center.restoreStandard()
        #expect(center.isStandard)
        #expect(PanelHotKeyCenter(preferences: preferences, isEnabled: false).hotKey == .standard)
    }

    @Test("Combinação já usada por outro app aparece como falha, e uma troca que dá certo a limpa")
    func refusedRegistrationIsReported() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let registrar = FakeRegistrar()
        registrar.nextStatus = OSStatus(eventHotKeyExistsErr)
        let center = PanelHotKeyCenter(preferences: preferences, registrar: registrar, isEnabled: true)
        center.setOwner(true)

        #expect(center.failure == .inUse)
        #expect(!center.isActive)
        #expect(center.failure?.message == "Outro app já usa este atalho. Escolha outra combinação.")

        registrar.nextStatus = noErr
        center.update(to: try #require(PanelHotKey(keyCode: UInt16(kVK_ANSI_K), modifiers: [.command, .control])))
        #expect(center.failure == nil)
        #expect(center.isActive)
    }

    @Test("Enquanto os Ajustes gravam uma combinação, o atalho fica solto e volta no fim")
    func recordingReleasesTheShortcut() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let registrar = FakeRegistrar()
        let center = PanelHotKeyCenter(preferences: preferences, registrar: registrar, isEnabled: true)
        center.setOwner(true)

        center.setRecording(true)
        #expect(registrar.registered == nil)
        #expect(!center.isActive)
        center.setRecording(false)
        #expect(registrar.registered == .standard)
        #expect(center.isActive)
    }

    @Test("Fora do ambiente permitido (os testes do app), o atalho nunca é registrado")
    func disabledEnvironmentNeverRegisters() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        let registrar = FakeRegistrar()
        let center = PanelHotKeyCenter(preferences: preferences, registrar: registrar, isEnabled: false)
        center.setOwner(true)

        #expect(registrar.registrations.isEmpty)
        #expect(!center.isActive)
        #expect(!PanelHotKeyCenter.isAllowedByEnvironment, "este próprio teste roda no ambiente dos testes do app")
    }

    @Test("Um valor guardado que não se lê vale como o padrão")
    func unreadableValueFallsBackToStandard() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(Data("não é json".utf8), forKey: PanelHotKeyCenter.hotKeyKey)
        #expect(PanelHotKeyCenter(preferences: preferences, isEnabled: false).hotKey == .standard)
    }

    private static func makePreferences() throws -> (UserDefaults, String) {
        let suite = "PanelHotKeyTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}
