import AppKit

// Source app names / icons from the store (own copies), with in-memory caching.
final class SourceAppDirectory {
    static let shared = SourceAppDirectory()

    private var names: [String: String] = [:]     // bundle id → name
    private var icons: [String: NSImage] = [:]

    func reload(from store: ClipboardStore) {
        names = Dictionary(store.sourceApps().map { ($0.bundleID, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    func name(for bundleID: String) -> String? {
        names[bundleID]
    }

    func icon(for bundleID: String?, store: ClipboardStore?) -> NSImage? {
        guard let bundleID else { return nil }
        if let image = icons[bundleID] { return image }
        var image = store?.sourceIcon(bundleID: bundleID).flatMap { NSImage(data: $0) }
        if image == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        if let image { icons[bundleID] = image }
        return image
    }

    // "Name::" → bundle id: exact name, then prefix, then bundle id (case-insensitive).
    func resolve(name raw: String) -> String? {
        let name = raw.lowercased()
        if let hit = names.first(where: { $0.value.lowercased() == name }) { return hit.key }
        let prefixed = names.filter { $0.value.lowercased().hasPrefix(name) }
        if let hit = prefixed.min(by: { $0.value.count < $1.value.count }) { return hit.key }
        return names.keys.first { $0.lowercased() == name }
    }
}

// Async downsampled image loading for list rows and the preview.
final class ClipThumbnailCache {
    static let shared = ClipThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var pending: [String: [(NSImage?) -> Void]] = [:]

    init() {
        cache.countLimit = 300
    }

    func cached(uuid: String, maxPixel: Int) -> NSImage? {
        cache.object(forKey: "\(uuid)-\(maxPixel)" as NSString)
    }

    func load(uuid: String, url: URL, maxPixel: Int, completion: @escaping (NSImage?) -> Void) {
        let key = "\(uuid)-\(maxPixel)"
        if let image = cache.object(forKey: key as NSString) {
            completion(image)
            return
        }
        if pending[key] != nil {
            pending[key]?.append(completion)
            return
        }
        pending[key] = [completion]
        Task { [weak self] in
            // Default QoS (.medium): ImageIO decodes on default-QoS workers, a higher caller QoS
            // would wait on them (priority inversion / hang-risk warning).
            let box = await Task.detached(priority: .medium) {
                ClipImageCodec.thumbnail(url: url, maxPixel: maxPixel).map { CGImageBox(image: $0) }
            }.value
            guard let self else { return }
            let image = box.map { NSImage(cgImage: $0.image, size: .zero) }
            if let image { self.cache.setObject(image, forKey: key as NSString) }
            let callbacks = self.pending.removeValue(forKey: key) ?? []
            callbacks.forEach { $0(image) }
        }
    }
}

// Font from a family name ("" = system font).
enum ClipboardFonts {
    static func make(family: String, size: Int) -> NSFont {
        let pointSize = CGFloat(size)
        guard !family.isEmpty,
              let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: pointSize)
        else { return .systemFont(ofSize: pointSize) }
        return font
    }

    static func lineHeight(_ font: NSFont) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: font)
    }
}

// Clipboard background colors and "#RRGGBB" conversion.
enum ClipboardColors {
    static let lightGray = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1)
    static let darkGray = NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1)

    static func color(hex: String) -> NSColor? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    // Dark backgrounds get the dark appearance (white text).
    static func isDark(_ color: NSColor) -> Bool {
        let c = color.usingColorSpace(.sRGB) ?? color
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance < 0.5
    }
}
