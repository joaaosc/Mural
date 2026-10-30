import Foundation
import Testing

@testable import Mural

@Suite("Ponto do miniplayer")
@MainActor
struct NowPlayingDockStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "NowPlayingDockStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Sem nada guardado, começa à esquerda")
    func defaultsToLeading() {
        #expect(NowPlayingDockStore(preferences: makeDefaults(), readsStoredValue: true).dock == .leading)
    }

    @Test("Grava a mudança e lê de volta")
    func savesAndReads() {
        let defaults = makeDefaults()
        let store = NowPlayingDockStore(preferences: defaults, readsStoredValue: true)
        store.dock = .trailing
        #expect(defaults.string(forKey: NowPlayingDockStore.key) == "trailing")
        #expect(NowPlayingDockStore(preferences: defaults, readsStoredValue: true).dock == .trailing)
    }

    @Test("Valor desconhecido vale como esquerda")
    func invalidValueFallsBack() {
        let defaults = makeDefaults()
        defaults.set("meio", forKey: NowPlayingDockStore.key)
        #expect(NowPlayingDockStore(preferences: defaults, readsStoredValue: true).dock == .leading)
    }

    @Test("Sem ler o valor guardado, começa à esquerda")
    func ignoresStoredValueWhenNotReading() {
        let defaults = makeDefaults()
        defaults.set("center", forKey: NowPlayingDockStore.key)
        #expect(NowPlayingDockStore(preferences: defaults, readsStoredValue: false).dock == .leading)
    }
}
