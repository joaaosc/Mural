import Carbon.HIToolbox

/// Quem registra o atalho no sistema. Existe para os testes trocarem o registro de verdade por um falso: registrar uma
/// combinação de verdade a tira de todos os apps de quem roda os testes.
@MainActor
protocol HotKeyRegistrar: AnyObject {
    /// Registra a combinação no lugar da anterior.
    /// - Returns: `noErr`, ou o erro do sistema (`eventHotKeyExistsErr` quando outro app já tem a combinação).
    func register(_ hotKey: PanelHotKey) -> OSStatus
    /// Tira a combinação registrada, se houver.
    func unregister()
}

/// O registro de verdade, pela API de atalhos do Carbon (`RegisterEventHotKey`): funciona no App Sandbox e sem a
/// permissão de Acessibilidade, ao contrário de observar o teclado de todos os apps.
///
/// Vive o app inteiro (`PanelHotKeyCenter.shared`), por isso não desfaz o tratador ao sair: o sistema passa o próprio
/// objeto ao tratador sem retê-lo.
@MainActor
final class CarbonHotKeyRegistrar: HotKeyRegistrar {
    /// A assinatura dos atalhos do Mural ('MURL'). O sistema entrega ao tratador todo atalho do app, e é por ela, mais o
    /// identificador, que o tratador sabe que o atalho é este.
    private nonisolated static let signature: OSType = 0x4D55_524C
    private nonisolated static let identifier: UInt32 = 1

    private let action: @MainActor () -> Void
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// - Parameter action: o que o atalho faz; chamado no ator principal.
    init(action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func register(_ hotKey: PanelHotKey) -> OSStatus {
        installHandlerIfNeeded()
        unregister()
        var registered: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotKey.keyCode, hotKey.carbonModifiers, EventHotKeyID(signature: Self.signature, id: Self.identifier),
            GetApplicationEventTarget(), 0, &registered)
        if status == noErr { reference = registered }
        return status
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                guard status == noErr, hotKeyID.signature == CarbonHotKeyRegistrar.signature,
                    hotKeyID.id == CarbonHotKeyRegistrar.identifier
                else { return OSStatus(eventNotHandledErr) }
                // O sistema entrega os atalhos no laço principal, que é o do ator principal.
                return MainActor.assumeIsolated {
                    Unmanaged<CarbonHotKeyRegistrar>.fromOpaque(userData).takeUnretainedValue().action()
                    return noErr
                }
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}
