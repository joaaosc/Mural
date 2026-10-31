import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Mural

@Suite("Paleta de cores")
@MainActor
struct ThemePaletteTests {
    private func makeDefaults() -> UserDefaults {
        let name = "ThemePaletteTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Nos testes, a paleta escolhida neste Mac não vale: as preferências são de um conjunto próprio")
    func testsIgnoreThePaletteOfTheApp() {
        #expect(ThemeStore.defaultPreferences() !== UserDefaults.standard)
        #expect(ThemeStore.shared.palette == .neutral)
    }

    @Test("Sem nada guardado, começa no neutro")
    func defaultsToNeutral() {
        #expect(ThemeStore(preferences: makeDefaults()).palette == .neutral)
    }

    @Test("Grava a mudança e lê de volta")
    func savesAndReads() {
        let defaults = makeDefaults()
        let store = ThemeStore(preferences: defaults)
        store.palette = .warm
        #expect(defaults.string(forKey: ThemeStore.key) == "warm")
        #expect(ThemeStore(preferences: defaults).palette == .warm)
    }

    @Test("Valor desconhecido vale como neutro")
    func invalidValueFallsBack() {
        let defaults = makeDefaults()
        defaults.set("roxo", forKey: ThemeStore.key)
        #expect(ThemeStore(preferences: defaults).palette == .neutral)
    }

    /// As aparências de alto contraste só existem como aparência efetiva com a opção do sistema ligada
    /// (`NSAppearance(named:)` devolve a comum), então ficam fora daqui: conferir à mão com Aumentar Contraste.
    @Test("Toda paleta resolve as cores no claro e no escuro, com o papel mais claro que o mural")
    func everyPaletteResolves() {
        for palette in ThemePalette.allCases {
            let colors = palette.colors
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let canvas = Self.resolved(colors.canvas, in: appearance)
                let paper = Self.resolved(colors.paper, in: appearance)
                // Nos dois modos o papel é mais claro que o mural: é o que faz o cartão se destacar.
                #expect(
                    paper.brightnessComponent > canvas.brightnessComponent,
                    "\(palette) em \(appearance.rawValue): o papel é mais claro que o mural")
            }
        }
    }

    @Test("O escuro das paletas com matiz é mais claro que o quase-preto do neutro")
    func tintedDarkIsLighterThanNeutral() {
        let neutral = Self.resolved(ThemePalette.neutral.colors.canvas, in: .darkAqua).brightnessComponent
        for palette in ThemePalette.allCases where palette != .neutral {
            #expect(Self.resolved(palette.colors.canvas, in: .darkAqua).brightnessComponent > neutral)
        }
    }

    /// A cor resolvida numa aparência, em sRGB.
    private static func resolved(_ color: Color, in appearance: NSAppearance.Name) -> NSColor {
        var result = NSColor.clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            result = NSColor(color).usingColorSpace(.sRGB) ?? .clear
        }
        return result
    }
}
