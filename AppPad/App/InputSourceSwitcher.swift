import Carbon

// Switches the keyboard input source to an English (ASCII-capable) layout while the
// launcher is open, and puts the previous one back when it closes — unless the user
// changed input source manually in between.
enum InputSourceSwitcher {
    private static var previousID: String?
    private static var selectedID: String?

    static func switchToASCII() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let ascii = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let currentID = sourceID(current), let asciiID = sourceID(ascii) else { return }
        guard currentID != asciiID else { return }   // already English
        if TISSelectInputSource(ascii) == OSStatus(noErr) {
            previousID = currentID
            selectedID = asciiID
        }
    }

    static func restore() {
        defer {
            previousID = nil
            selectedID = nil
        }
        guard let previousID, let selectedID,
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              sourceID(current) == selectedID,          // user did not switch manually
              let previous = source(withID: previousID) else { return }
        TISSelectInputSource(previous)
    }

    private static func sourceID(_ source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func source(withID id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        return list.first
    }
}
