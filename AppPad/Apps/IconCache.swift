import AppKit

// App icon cache keyed by bundle path.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for app: AppInfo) -> NSImage {
        let path = app.url.path
        if let image = cache[path] { return image }
        // Resolve symlinks (Safari) so the icon is the target app's, never a link icon.
        let image = NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        image.size = NSSize(width: 128, height: 128)
        cache[path] = image
        return image
    }

    func invalidate() {
        cache.removeAll()
    }
}
