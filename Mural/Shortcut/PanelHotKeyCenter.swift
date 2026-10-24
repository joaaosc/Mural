import Carbon.HIToolbox
import Foundation
import Observation

/// Por que o atalho escolhido não está valendo.
enum PanelHotKeyFailure: Equatable, Sendable {
    /// Outro app (ou o próprio macOS) já tem a combinação: o sistema recusa o registro, e os Ajustes mostram o motivo em
    /// vez de fingir que deu certo.
    case inUse
    /// O sistema recusou por outro motivo, com o código do erro.
    case refused(OSStatus)

    var message: String {
        switch self {
        case .inUse: "Outro app já usa este atalho. Escolha outra combinação."
        case .refused(let status): "O macOS recusou este atalho (erro \(status))."
        }
    }
}

/// O atalho de teclado que abre o painel da barra de menus de qualquer app: qual é, se está valendo e por quê não.
///
/// Começa em ⌘` (``PanelHotKey/standard``) até a pessoa escolher outro nos Ajustes; tirar o atalho também fica guardado,
/// para ele não voltar sozinho. Só a cópia do Mural que mostra o ícone da barra de menus registra o atalho
/// (``setOwner(_:)``, chamado por `MenuBarIconCoordinator`): com duas cópias abertas, as duas abririam um painel.
///
/// Nos testes (os do app e os de interface) o atalho de verdade nunca é registrado: ele tiraria a combinação de todos os
/// apps de quem roda os testes. Os testes deste modelo usam um registro falso.
@MainActor
@Observable
final class PanelHotKeyCenter {
    static let shared = PanelHotKeyCenter()

    /// A chave do atalho escolhido, em JSON.
    static let hotKeyKey = "menuBarPanelHotKey"
    /// A chave que marca que a pessoa tirou o atalho.
    static let removedKey = "menuBarPanelHotKeyRemoved"

    /// O atalho escolhido: o guardado; o padrão se a pessoa nunca escolheu; `nil` se ela o tirou.
    private(set) var hotKey: PanelHotKey?
    /// Por que o atalho não está valendo; `nil` quando vale, quando não há atalho e quando esta cópia não é a dona do
    /// ícone.
    private(set) var failure: PanelHotKeyFailure?
    /// O atalho está registrado no sistema agora.
    private(set) var isActive = false

    /// O atalho é o padrão (⌘`).
    var isStandard: Bool { hotKey == .standard }

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private var registrar: (any HotKeyRegistrar)?
    /// Esta cópia do Mural é a que mostra o ícone e responde ao atalho.
    @ObservationIgnored private var isOwner = false
    /// Os Ajustes estão gravando uma combinação nova: o atalho fica solto, para apertá-lo gravar em vez de abrir o painel.
    @ObservationIgnored private var isRecording = false

    /// - Parameters:
    ///   - preferences: onde o atalho fica guardado.
    ///   - registrar: quem registra no sistema; `nil` deixa para ``start(action:)`` criar o de verdade.
    ///   - isEnabled: `false` nunca registra nada. `nil` decide pelo ambiente: falso nos testes do app e nos de interface.
    init(
        preferences: UserDefaults = .standard,
        registrar: (any HotKeyRegistrar)? = nil,
        isEnabled: Bool? = nil
    ) {
        self.preferences = preferences
        self.registrar = registrar
        self.isEnabled = isEnabled ?? Self.isAllowedByEnvironment
        hotKey = Self.storedHotKey(in: preferences)
    }

    /// Fora dos testes do app e dos de interface.
    static var isAllowedByEnvironment: Bool {
        !LaunchConfiguration.isUITesting && ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    /// Diz o que o atalho faz e cria o registro de verdade, se nenhum foi dado. Uma cópia que já é a dona do ícone
    /// registra o atalho na hora.
    func start(action: @escaping @MainActor () -> Void) {
        if registrar == nil { registrar = CarbonHotKeyRegistrar(action: action) }
        apply()
    }

    /// Esta cópia passou a mostrar o ícone (`true`) ou deixou de mostrar (`false`): só a dona registra o atalho.
    func setOwner(_ owner: Bool) {
        guard owner != isOwner else { return }
        isOwner = owner
        apply()
    }

    /// Solta o atalho enquanto os Ajustes gravam uma combinação nova (`true`) e o registra de novo no fim (`false`).
    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        apply()
    }

    /// Guarda a combinação nova e a registra no lugar da anterior.
    func update(to hotKey: PanelHotKey) {
        self.hotKey = hotKey
        preferences.set(try? JSONEncoder().encode(hotKey), forKey: Self.hotKeyKey)
        preferences.removeObject(forKey: Self.removedKey)
        apply()
    }

    /// Volta ao atalho padrão (⌘`).
    func restoreStandard() {
        update(to: .standard)
    }

    /// Tira o atalho: o painel só abre pelo ícone e pelo menu do app, até a pessoa escolher outro.
    func remove() {
        hotKey = nil
        preferences.removeObject(forKey: Self.hotKeyKey)
        preferences.set(true, forKey: Self.removedKey)
        apply()
    }

    /// Deixa o registro no sistema de acordo com o estado: registrado só com atalho, com permissão do ambiente, com o
    /// registro pronto, sendo a dona do ícone e fora de uma gravação.
    private func apply() {
        registrar?.unregister()
        isActive = false
        failure = nil
        guard isEnabled, isOwner, !isRecording, let hotKey, let registrar else { return }
        let status = registrar.register(hotKey)
        switch status {
        case noErr:
            isActive = true
        case OSStatus(eventHotKeyExistsErr):
            failure = .inUse
        default:
            failure = .refused(status)
        }
    }

    /// O atalho guardado; o padrão se nada foi guardado; `nil` se a pessoa o tirou. Um valor que não se lê vale como o
    /// padrão.
    private static func storedHotKey(in preferences: UserDefaults) -> PanelHotKey? {
        if preferences.bool(forKey: removedKey) { return nil }
        guard let data = preferences.data(forKey: hotKeyKey),
            let hotKey = try? JSONDecoder().decode(PanelHotKey.self, from: data)
        else { return .standard }
        return hotKey
    }
}
