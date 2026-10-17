import AppKit
import QuartzCore

// App icon cache keyed by bundle path.
final class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]
    // Layer-ready icon renders (path@scale): folder morph proxies reuse them instead of
    // re-resolving the icon every time a folder opens or closes.
    private var contentsCache: [String: (contents: Any, scale: CGFloat)] = [:]
    private var warmQueue: [AppInfo] = []
    private var warmScale: CGFloat = 2
    private var warmTask: Task<Void, Never>?

    func icon(for app: AppInfo) -> NSImage {
        icon(path: app.url.path)
    }

    func icon(path: String) -> NSImage {
        if let image = cache[path] { return image }
        // Resolve symlinks (Safari) so the icon is the target app's, never a link icon.
        let image = NSWorkspace.shared.icon(forFile: URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
        image.size = NSSize(width: 128, height: 128)
        cache[path] = image
        return image
    }

    // Same contents an image view would put in its layer (NSImage → layer at this scale).
    func layerContents(for app: AppInfo, scale: CGFloat) -> (contents: Any, scale: CGFloat) {
        let image = icon(for: app)
        let contentsScale = image.recommendedLayerContentsScale(scale)
        let key = "\(app.url.path)@\(contentsScale)"
        if let hit = contentsCache[key] { return hit }
        let entry = (contents: image.layerContents(forContentsScale: contentsScale), scale: contentsScale)
        contentsCache[key] = entry
        return entry
    }

    // Render icons ahead in small idle slices (a few ms each), so the work never lands
    // in a single frame. A new call replaces the pending queue.
    func warm(_ apps: [AppInfo], scale: CGFloat) {
        warmQueue = apps
        warmScale = scale
        guard warmTask == nil, !apps.isEmpty else { return }
        warmTask = Task { [weak self] in
            while let self, !self.warmQueue.isEmpty {
                try? await Task.sleep(for: .milliseconds(30))
                guard !Task.isCancelled else { return }
                let deadline = CACurrentMediaTime() + 0.004
                repeat {
                    let app = self.warmQueue.removeFirst()
                    _ = self.layerContents(for: app, scale: self.warmScale)
                } while !self.warmQueue.isEmpty && CACurrentMediaTime() < deadline
            }
            self?.warmTask = nil
        }
    }

    func invalidate() {
        warmTask?.cancel()
        warmTask = nil
        warmQueue.removeAll()
        cache.removeAll()
        contentsCache.removeAll()
    }
}
