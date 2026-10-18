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
        guard app.isInstalling else { return icon(path: app.url.path) }
        // Download placeholder: the App Store puts the real icon next to the stub Info.plist.
        let path = app.url.path
        if let image = cache[path] { return image }
        let png = AppScanner.wrappedApp(in: app.url.resolvingSymlinksInPath())?.appendingPathComponent("Icon.png")
        let image = png.flatMap { NSImage(contentsOf: $0) } ?? NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 128, height: 128)
        cache[path] = image
        return image
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

    // Drop only these apps (late icon refresh after an install).
    func invalidate(paths: [String]) {
        AppThumbnailCache.shared.invalidate(paths: paths)
        let set = Set(paths)
        for path in set { cache[path] = nil }
        contentsCache = contentsCache.filter { key, _ in
            guard let at = key.lastIndex(of: "@") else { return true }
            return !set.contains(String(key[..<at]))
        }
    }

    func invalidate() {
        AppThumbnailCache.shared.invalidate()
        warmTask?.cancel()
        warmTask = nil
        warmQueue.removeAll()
        cache.removeAll()
        contentsCache.removeAll()
    }
}

// Small pre-rendered app icons for long lists (Settings › App Shortcuts).
// Bitmaps at the final pixel size: rows draw them as-is instead of resolving a multi-size
// workspace icon per row. Rendered off the main thread; thread-safe.
nonisolated final class AppThumbnailCache: @unchecked Sendable {
    static let shared = AppThumbnailCache()
    static let pointSize: CGFloat = 22
    static let scale: CGFloat = 2

    private let lock = NSLock()
    private var images: [String: CGImage] = [:]

    // Cached thumbnail, rendered now on a miss.
    func image(path: String) -> CGImage? {
        if let hit = cached(path) { return hit }
        guard let image = Self.render(path: path) else { return nil }
        store(image, path)
        return image
    }

    // Render all missing thumbnails in parallel (call off the main thread).
    func prewarm(paths: [String]) {
        let missing = Array(Set(paths).filter { cached($0) == nil })
        guard !missing.isEmpty else { return }
        DispatchQueue.concurrentPerform(iterations: missing.count) { i in
            if let image = Self.render(path: missing[i]) { store(image, missing[i]) }
        }
    }

    func invalidate(paths: [String]) {
        lock.lock()
        for path in paths { images[path] = nil }
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        images.removeAll()
        lock.unlock()
    }

    private func cached(_ path: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return images[path]
    }

    private func store(_ image: CGImage, _ path: String) {
        lock.lock()
        images[path] = image
        lock.unlock()
    }

    // Workspace icon (symlinks resolved, like IconCache) drawn into a pointSize × scale bitmap.
    private static func render(path: String) -> CGImage? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let icon = NSWorkspace.shared.icon(forFile: resolved)
        let side = Int(pointSize * scale)
        var proposed = CGRect(x: 0, y: 0, width: side, height: side)
        guard let source = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}
