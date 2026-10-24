import CoreGraphics
import Foundation
import Testing

@testable import Mural

/// O painel da barra de menus arrastado pela pessoa: a conta de onde ele reabre e o lugar guardado nas preferências.
@Suite("Lugar do painel da barra de menus")
@MainActor
struct MenuBarPanelPositionTests {
    private let main = CGRect(x: 0, y: 0, width: 1440, height: 875)
    /// Um segundo monitor à esquerda do principal, com a origem negativa.
    private let left = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
    private let size = CGSize(width: 600, height: 400)

    // MARK: Conta

    @Test("O painel reabre com o canto de cima à esquerda onde foi deixado")
    func reopensWhereItWasLeft() {
        let frame = MenuBarPanelPlacement.frame(size: size, topLeft: CGPoint(x: 300, y: 700), visibleFrames: [main])
        #expect(frame == CGRect(x: 300, y: 300, width: 600, height: 400))
    }

    @Test("Mais alto que o espaço embaixo do canto, o painel sobe até caber na tela")
    func tallPanelMovesUpToFit() {
        let frame = MenuBarPanelPlacement.frame(size: size, topLeft: CGPoint(x: 300, y: 250), visibleFrames: [main])
        #expect(frame == CGRect(x: 300, y: 0, width: 600, height: 400))
    }

    @Test("Perto da borda direita, o painel volta para dentro da tela")
    func nearTheRightEdgeStaysOnScreen() {
        let frame = MenuBarPanelPlacement.frame(size: size, topLeft: CGPoint(x: 1300, y: 600), visibleFrames: [main])
        #expect(frame?.maxX == main.maxX)
        #expect(frame?.maxY == 600)
    }

    @Test("Encostado no alto da área visível ainda conta como dentro da tela")
    func topEdgeCountsAsInside() {
        let frame = MenuBarPanelPlacement.frame(size: size, topLeft: CGPoint(x: 100, y: main.maxY), visibleFrames: [main])
        #expect(frame?.maxY == main.maxY)
    }

    @Test("O canto num segundo monitor, com origem negativa, fica nele")
    func keepsTheSecondScreen() {
        let frame = MenuBarPanelPlacement.frame(size: size, topLeft: CGPoint(x: -1000, y: 900), visibleFrames: [main, left])
        #expect(frame == CGRect(x: -1000, y: 500, width: 600, height: 400))
    }

    @Test("Sem tela que contenha o canto (monitor desligado) ou com um ponto inválido, não há lugar guardado que valha")
    func missingScreenFallsBack() {
        #expect(MenuBarPanelPlacement.frame(size: size, topLeft: CGPoint(x: -1000, y: 900), visibleFrames: [main]) == nil)
        #expect(MenuBarPanelPlacement.frame(size: size, topLeft: CGPoint(x: CGFloat.nan, y: 10), visibleFrames: [main]) == nil)
    }

    @Test("Prender à tela não muda o tamanho, e o canto guardado é o de cima à esquerda")
    func clampingKeepsTheSize() {
        let outside = CGRect(x: -50, y: -80, width: 600, height: 400)
        let clamped = MenuBarPanelPlacement.clamped(outside, to: main)
        #expect(clamped == CGRect(x: 0, y: 0, width: 600, height: 400))
        #expect(MenuBarPanelPlacement.topLeft(of: clamped) == CGPoint(x: 0, y: 400))
    }

    // MARK: Preferências

    @Test("Guardar e reabrir: um modelo novo lê o lugar; esquecer apaga")
    func savedPlaceSurvivesANewModel() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }

        let position = MenuBarPanelPosition(preferences: preferences)
        #expect(position.remembersPosition, "lembrar começa ligado")
        #expect(position.topLeftToRestore == nil, "nunca arrastado, abre no lugar de sempre")

        position.save(topLeft: CGPoint(x: 120, y: 640))
        #expect(MenuBarPanelPosition(preferences: preferences).topLeftToRestore == CGPoint(x: 120, y: 640))

        position.forget()
        #expect(MenuBarPanelPosition(preferences: preferences).savedTopLeft == nil)
    }

    @Test("Desligar lembrar esquece o lugar e não guarda os próximos arrastos")
    func turningOffForgetsAndStopsSaving() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }

        let position = MenuBarPanelPosition(preferences: preferences)
        position.save(topLeft: CGPoint(x: 10, y: 20))
        position.remembersPosition = false
        #expect(position.savedTopLeft == nil)
        position.save(topLeft: CGPoint(x: 30, y: 40))
        #expect(position.topLeftToRestore == nil)

        let reopened = MenuBarPanelPosition(preferences: preferences)
        #expect(!reopened.remembersPosition)
        #expect(reopened.savedTopLeft == nil)
    }

    @Test("Um valor guardado que não é um par de números vale como nada guardado")
    func malformedValueIsIgnored() throws {
        let (preferences, suite) = try Self.makePreferences()
        defer { preferences.removePersistentDomain(forName: suite) }

        preferences.set(["x", "y"], forKey: MenuBarPanelPosition.topLeftKey)
        #expect(MenuBarPanelPosition(preferences: preferences).savedTopLeft == nil)
        preferences.set([1.0, 2.0, 3.0], forKey: MenuBarPanelPosition.topLeftKey)
        #expect(MenuBarPanelPosition(preferences: preferences).savedTopLeft == nil)
    }

    private static func makePreferences() throws -> (UserDefaults, String) {
        let suite = "MenuBarPanelPositionTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}
