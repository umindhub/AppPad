import AppKit
import ApplicationServices
import Carbon.HIToolbox

// Writes an item back to the pasteboard and optionally sends ⌘V to the frontmost app
// (needs Accessibility permission).
// PNG + TIFF for an image item, built off the main thread (decode is slow for large images).
nonisolated struct PasteImageData: Sendable {
    let png: Data?
    let tiff: Data?
}

enum PasteService {
    nonisolated static func imageData(url: URL) -> PasteImageData? {
        guard let image = ClipImageCodec.fullImage(url: url) else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return PasteImageData(png: rep.representation(using: .png, properties: [:]), tiff: rep.tiffRepresentation)
    }

    // Returns the pasteboard change count after writing. Image items need `image` prepared beforehand.
    @discardableResult
    static func write(_ item: ClipItem, image: PasteImageData?) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            let pbItem = NSPasteboardItem()
            if let rtf = item.rtf { pbItem.setData(rtf, forType: .rtf) }
            pbItem.setString(item.text ?? "", forType: .string)
            pasteboard.writeObjects([pbItem])
        case .file:
            let paths = (item.text ?? "").split(separator: "\n").map(String.init)
            pasteboard.writeObjects(fileItems(paths: paths))
        case .image:
            guard let image else { break }
            let pbItem = NSPasteboardItem()
            if let png = image.png { pbItem.setData(png, forType: .png) }
            if let tiff = image.tiff { pbItem.setData(tiff, forType: .tiff) }
            // Image copied as a file: while the original exists, Finder pastes the file
            // and text fields paste its path (same types Finder itself writes).
            if let path = item.sourcePath, FileManager.default.fileExists(atPath: path) {
                pbItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                pbItem.setString(path, forType: .string)
            }
            pasteboard.writeObjects([pbItem])
        }
        return pasteboard.changeCount
    }

    // One item per existing file (Finder reads every file URL and pastes the files);
    // the first item also carries all paths as plain text, which text fields paste.
    private static func fileItems(paths: [String]) -> [NSPasteboardItem] {
        var items = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { path -> NSPasteboardItem in
                let pbItem = NSPasteboardItem()
                pbItem.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                return pbItem
            }
        if items.isEmpty { items = [NSPasteboardItem()] }   // all files gone: text path only
        items[0].setString(paths.joined(separator: "\n"), forType: .string)
        return items
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    // Shows the system prompt (once per app identity).
    static func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // Delay lets the previous app's window become key again after our panel closes.
    static func sendPasteKeystroke(after delay: TimeInterval = 0.08) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let key = CGKeyCode(kVK_ANSI_V)
            let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
