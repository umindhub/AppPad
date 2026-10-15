import Carbon.HIToolbox

// Window control commands; each has its own customizable global shortcut.
nonisolated enum WindowAction: String, CaseIterable, Codable, Sendable {
    case snapLeft, snapRight, snapTop, snapBottom, maximize, restore, previousDisplay, nextDisplay

    // ⌃⌥←/→/↑/↓ snap, ⌃⌥↩ maximize, ⌃⌥⌫ restore, ⌃⌥⌘↑/↓ move between displays.
    var defaultCombo: KeyCombo {
        let ctrlOpt = UInt32(controlKey | optionKey)
        let ctrlOptCmd = ctrlOpt | UInt32(cmdKey)
        switch self {
        case .snapLeft:
            return KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOpt, keyLabel: "←")
        case .snapRight:
            return KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOpt, keyLabel: "→")
        case .snapTop:
            return KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: ctrlOpt, keyLabel: "↑")
        case .snapBottom:
            return KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: ctrlOpt, keyLabel: "↓")
        case .maximize:
            return KeyCombo(keyCode: UInt32(kVK_Return), modifiers: ctrlOpt, keyLabel: "↩")
        case .restore:
            return KeyCombo(keyCode: UInt32(kVK_Delete), modifiers: ctrlOpt, keyLabel: "⌫")
        case .previousDisplay:
            return KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: ctrlOptCmd, keyLabel: "↑")
        case .nextDisplay:
            return KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: ctrlOptCmd, keyLabel: "↓")
        }
    }

    static var defaultCombos: [WindowAction: KeyCombo] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.defaultCombo) })
    }

    var title: String {
        switch self {
        case .snapLeft: return String(localized: "Snap Left")
        case .snapRight: return String(localized: "Snap Right")
        case .snapTop: return String(localized: "Snap Top")
        case .snapBottom: return String(localized: "Snap Bottom")
        case .maximize: return String(localized: "Maximize")
        case .restore: return String(localized: "Restore")
        case .previousDisplay: return String(localized: "Move to Previous Display")
        case .nextDisplay: return String(localized: "Move to Next Display")
        }
    }

    var detail: String {
        switch self {
        case .snapLeft: return String(localized: "Left ½ → ⅓ → ⅔ on each press")
        case .snapRight: return String(localized: "Right ½ → ⅓ → ⅔ on each press")
        case .snapTop: return String(localized: "Top ½ → ⅓ → ⅔ on each press")
        case .snapBottom: return String(localized: "Bottom ½ → ⅓ → ⅔ on each press")
        case .maximize: return String(localized: "Fill the screen without entering full screen")
        case .restore: return String(localized: "Back to the size and position before snapping")
        case .previousDisplay, .nextDisplay: return String(localized: "Keeps the snapped layout on the new display")
        }
    }

    var symbol: String {
        switch self {
        case .snapLeft: return "rectangle.lefthalf.filled"
        case .snapRight: return "rectangle.righthalf.filled"
        case .snapTop: return "rectangle.tophalf.filled"
        case .snapBottom: return "rectangle.bottomhalf.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .restore: return "arrow.uturn.backward"
        case .previousDisplay: return "arrow.up.square"
        case .nextDisplay: return "arrow.down.square"
        }
    }
}
