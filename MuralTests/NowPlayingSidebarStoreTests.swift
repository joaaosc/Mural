import Foundation
import Testing

@testable import Mural

@Suite("Miniplayer na barra lateral")
@MainActor
struct NowPlayingSidebarStoreTests {
    private func makeDefaults() -> UserDefaults {
        let name = "NowPlayingSidebarStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Sem nada guardado, o miniplayer não está na barra lateral")
    func defaultsToOff() {
        #expect(!NowPlayingSidebarStore(preferences: makeDefaults(), readsStoredValue: true).isInSidebar)
    }

    @Test("Grava a ida para a barra lateral e a volta, e lê de novo")
    func savesAndReads() {
        let defaults = makeDefaults()
        let store = NowPlayingSidebarStore(preferences: defaults, readsStoredValue: true)
        store.isInSidebar = true
        #expect(defaults.bool(forKey: NowPlayingSidebarStore.key))
        let reopened = NowPlayingSidebarStore(preferences: defaults, readsStoredValue: true)
        #expect(reopened.isInSidebar)

        reopened.isInSidebar = false
        #expect(!defaults.bool(forKey: NowPlayingSidebarStore.key))
        #expect(!NowPlayingSidebarStore(preferences: defaults, readsStoredValue: true).isInSidebar)
    }

    @Test("Sem ler o valor guardado, começa fora da barra lateral")
    func ignoresStoredValueWhenNotReading() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: NowPlayingSidebarStore.key)
        #expect(!NowPlayingSidebarStore(preferences: defaults, readsStoredValue: false).isInSidebar)
    }
}
