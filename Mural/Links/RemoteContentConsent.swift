import MuralKit
import Observation
import SwiftUI

/// Quais murais importados de arquivo ainda não podem buscar prévias de link e capas de música na internet.
/// Envolve o `RemoteContentConsentStore` para que as telas reajam quando a pessoa permite.
@MainActor
@Observable
final class RemoteContentConsent {
    @ObservationIgnored private var store: RemoteContentConsentStore
    /// Sobe a cada mudança: o arquivo em si não notifica as telas, e quem leu `isBlocked` relê a view.
    private var revision = 0

    init(directory: URL) {
        store = RemoteContentConsentStore(directory: directory)
    }

    func isBlocked(_ id: BoardID) -> Bool {
        _ = revision
        return store.isBlocked(id)
    }

    /// Mural recém-importado de um arquivo: sem permissão até a pessoa dar.
    func block(_ id: BoardID) {
        store.block(id)
        revision &+= 1
    }

    /// A pessoa permitiu as buscas deste mural.
    func allow(_ id: BoardID) {
        store.allow(id)
        revision &+= 1
    }

    /// O mural foi apagado.
    func forget(_ id: BoardID) {
        store.forget(id)
        revision &+= 1
    }
}

extension EnvironmentValues {
    /// O mural da janela pode buscar prévias e capas na internet. `true` fora do app (nas prévias do Xcode).
    @Entry var remoteContentAllowed = true
}
