import Foundation

// Who owns a global shortcut (used to report duplicates in Settings).
enum ShortcutOwner: Equatable {
    case launcher, clipboard, clipboardSaved
    case app(String)            // AppHotKey.key
    case window(WindowAction)
}

extension Preferences {
    // Display name of another active owner with the same key + modifiers, if any.
    func conflictName(for combo: KeyCombo?, excluding owner: ShortcutOwner) -> String? {
        guard let combo else { return nil }
        func same(_ other: KeyCombo?) -> Bool {
            guard let other else { return false }
            return other.keyCode == combo.keyCode && other.modifiers == combo.modifiers
        }
        if owner != .launcher, same(launcherHotKey) { return String(localized: "AppPad") }
        if clipboardEnabled {
            if owner != .clipboard, same(clipboardHotKey) { return String(localized: "Clipboard") }
            if owner != .clipboardSaved, same(clipboardSavedHotKey) { return String(localized: "Saved items") }
        }
        if windowControlEnabled {
            for action in WindowAction.allCases where owner != .window(action) && same(windowHotKeys[action]) {
                return action.title
            }
        }
        return appHotKeys.first { owner != .app($0.key) && same($0.combo) }?.name
    }
}
