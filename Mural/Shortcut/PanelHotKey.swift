import AppKit
import Carbon.HIToolbox

/// Uma combinação de teclas que abre o painel da barra de menus de qualquer app.
///
/// Guardada pelo código da tecla e pelos modificadores, e não pelo caractere: a mesma tecla física dá caracteres
/// diferentes em cada leiaute de teclado, e o registro no sistema é feito pelo código.
nonisolated struct PanelHotKey: Codable, Equatable, Sendable {
    let keyCode: UInt32
    /// O valor cru de `NSEvent.ModifierFlags`, só com os modificadores aceitos (⌘ ⌥ ⌃ ⇧).
    let modifierFlags: UInt

    /// ⌘`: a tecla do acento grave, à esquerda do 1 nos teclados americanos (`kVK_ANSI_Grave`), com Command.
    ///
    /// No macOS a mesma combinação é "Mover o foco para a próxima janela" (Ajustes do Sistema › Teclado › Atalhos de
    /// Teclado); com aquele atalho ligado, o sistema pode ficar com ela, e os Ajustes do Mural mostram o motivo.
    static let standard = PanelHotKey(keyCode: UInt32(kVK_ANSI_Grave), modifierFlags: NSEvent.ModifierFlags.command.rawValue)

    /// Os modificadores que contam num atalho; o resto (Caps Lock, Fn) é ignorado.
    static let acceptedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt32, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(Self.acceptedModifiers).rawValue
    }

    /// A combinação de uma tecla apertada, se ela serve de atalho.
    ///
    /// Precisa de ⌘ ou ⌃: com só ⇧ ou ⌥ o atalho engoliria letras maiúsculas e os acentos que o ⌥ digita em todos os apps.
    /// Apertar só um modificador também não é atalho.
    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(Self.acceptedModifiers)
        guard !flags.isDisjoint(with: [.command, .control]), !Self.isModifierKey(keyCode) else { return nil }
        self.init(keyCode: UInt32(keyCode), modifierFlags: flags.rawValue)
    }

    /// A combinação de um evento de tecla; ver ``init(keyCode:modifiers:)``.
    init?(event: NSEvent) {
        self.init(keyCode: event.keyCode, modifiers: event.modifierFlags)
    }

    var flags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags).intersection(Self.acceptedModifiers)
    }

    /// Os modificadores no formato que o registro do Carbon pede.
    var carbonModifiers: UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        return mask
    }

    /// Os símbolos dos modificadores, na ordem do macOS (⌃⌥⇧⌘).
    var modifierSymbols: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text
    }

    /// Como o atalho aparece para a pessoa, com a tecla lida do leiaute de teclado atual: "⌘`", "⌃⌥Espaço".
    @MainActor
    var displayString: String {
        modifierSymbols + Self.keyName(for: keyCode)
    }

    private static let modifierKeys: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
        kVK_CapsLock, kVK_Function,
    ]

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        modifierKeys.contains(Int(keyCode))
    }

    /// O nome da tecla: as que não escrevem nada têm nome fixo; as outras são lidas do leiaute de teclado atual, para o
    /// nome ser o que a pessoa vê na tecla.
    @MainActor
    static func keyName(for keyCode: UInt32) -> String {
        if let name = namedKeys[Int(keyCode)] { return name }
        return typedCharacter(for: keyCode)?.uppercased() ?? "Tecla \(keyCode)"
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Espaço", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// O caractere que a tecla escreve no leiaute atual, sem modificadores e sem esperar o acento (uma tecla de acento,
    /// como o ` do teclado americano internacional, devolve o próprio acento).
    @MainActor
    private static func typedCharacter(for keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return OSStatus(paramErr) }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let text = String(utf16CodeUnits: characters, count: length)
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }
}
