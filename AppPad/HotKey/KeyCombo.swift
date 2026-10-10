import AppKit
import Carbon.HIToolbox

// A global shortcut: Carbon key code + Carbon modifier mask.
nonisolated struct KeyCombo: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyLabel: String

    // Default launcher shortcut: ⌥Space
    static let defaultLauncher = KeyCombo(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        keyLabel: "Space"
    )

    // Clipboard history: ⌘.   Saved items only: ⇧⌘.
    static let defaultClipboard = KeyCombo(
        keyCode: UInt32(kVK_ANSI_Period),
        modifiers: UInt32(cmdKey),
        keyLabel: "."
    )
    static let defaultClipboardSaved = KeyCombo(
        keyCode: UInt32(kVK_ANSI_Period),
        modifiers: UInt32(cmdKey | shiftKey),
        keyLabel: "."
    )

    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        // Stored label is English; localize the Space key name for display
        let key = keyCode == UInt32(kVK_Space) ? String(localized: "Space") : keyLabel
        return s + key
    }
}

extension KeyCombo {
    private static let specialLabels: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓", UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
    ]

    private static let functionKeys: [UInt16: String] = [
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
    ]

    // Build from a keyDown event; needs ⌘/⌥/⌃ unless it is a function key.
    @MainActor
    static func from(event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }

        let code = event.keyCode
        let isFunctionKey = functionKeys[code] != nil
        let hasPrimaryModifier = flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        guard hasPrimaryModifier || isFunctionKey else { return nil }

        let label = functionKeys[code] ?? specialLabels[code] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        guard !label.isEmpty else { return nil }
        return KeyCombo(keyCode: UInt32(code), modifiers: mods, keyLabel: label)
    }
}
