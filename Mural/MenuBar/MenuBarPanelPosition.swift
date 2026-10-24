import Foundation
import Observation

/// Onde a pessoa deixou o painel da barra de menus da última vez, e se ele deve voltar para lá.
///
/// Lembrar começa ligado: arrastar o painel já é dizer onde ele fica. Desligar (nos Ajustes) esquece o lugar, e o painel
/// volta a pender do ícone. As preferências guardam o canto de cima à esquerda como dois números, em coordenadas de tela
/// do AppKit (ver `MenuBarPanelPlacement`).
///
/// Lido e gravado direto nas preferências, e não por `@AppStorage`: a observação do `@Observable` não enxerga o
/// `@AppStorage`, e os Ajustes precisam ver a mudança na hora.
@MainActor
@Observable
final class MenuBarPanelPosition {
    static let shared = MenuBarPanelPosition()

    /// A chave do canto guardado: `[x, y]`.
    static let topLeftKey = "menuBarPanelTopLeft"
    /// A chave da opção de lembrar o lugar.
    static let remembersKey = "menuBarPanelRemembersPosition"

    /// O canto de cima à esquerda em que a pessoa deixou o painel; `nil` se ela nunca o arrastou, ou se o lugar foi
    /// esquecido.
    private(set) var savedTopLeft: CGPoint?
    /// Se o painel volta para onde foi deixado. Desligar esquece o lugar.
    var remembersPosition: Bool {
        didSet {
            preferences.set(remembersPosition, forKey: Self.remembersKey)
            if !remembersPosition { forget() }
        }
    }

    private let preferences: UserDefaults

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        remembersPosition = preferences.object(forKey: Self.remembersKey) as? Bool ?? true
        savedTopLeft = Self.point(from: preferences.array(forKey: Self.topLeftKey))
    }

    /// Onde abrir o painel: o canto guardado, se lembrar está ligado; senão `nil`, e o painel abre no lugar de sempre.
    var topLeftToRestore: CGPoint? {
        remembersPosition ? savedTopLeft : nil
    }

    /// Guarda o canto em que a pessoa deixou o painel. Com lembrar desligado, ou com um ponto que não é número, não faz nada.
    func save(topLeft: CGPoint) {
        guard remembersPosition, topLeft.x.isFinite, topLeft.y.isFinite else { return }
        savedTopLeft = topLeft
        preferences.set([Double(topLeft.x), Double(topLeft.y)], forKey: Self.topLeftKey)
    }

    /// Esquece o lugar: o painel volta a abrir junto do ícone (ou no meio da tela, pelo menu do app).
    func forget() {
        savedTopLeft = nil
        preferences.removeObject(forKey: Self.topLeftKey)
    }

    /// O ponto guardado como `[x, y]`; qualquer outra coisa (de uma versão futura ou estragada) vale como nada guardado.
    private static func point(from value: [Any]?) -> CGPoint? {
        guard let numbers = value as? [Double], numbers.count == 2, numbers.allSatisfy(\.isFinite) else { return nil }
        return CGPoint(x: numbers[0], y: numbers[1])
    }
}
