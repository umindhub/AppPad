import AppKit
import QuartzCore
import UniformTypeIdentifiers

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
    // Right after an install LaunchServices has not registered the bundle yet, and NSWorkspace
    // returns a blank placeholder tile (dashed outline on macOS 26). For freshly installed apps
    // the workspace icon is not used during a short grace period: the App Store download icon
    // (Icon.png) or the bundle's own .icns stands in, so the cell never flashes a blank tile.
    private var storeIcons: [String: NSImage] = [:]      // placeholder path → Icon.png (survives invalidate)
    private var installGrace: Set<String> = []           // just-installed paths, workspace icon not trusted yet
    private lazy var genericSignatures: [[UInt8]] = [
        NSWorkspace.shared.icon(for: .application),
        NSWorkspace.shared.icon(for: .applicationBundle),
        NSWorkspace.shared.icon(for: .folder),
    ].compactMap(Self.signature)

    func icon(for app: AppInfo) -> NSImage {
        guard app.isInstalling else { return icon(path: app.url.path) }
        // Download placeholder: the App Store puts the real icon next to the stub Info.plist.
        let path = app.url.path
        if let image = cache[path] { return image }
        let png = AppScanner.wrappedApp(in: app.url.resolvingSymlinksInPath())?.appendingPathComponent("Icon.png")
        let storeIcon = png.flatMap { NSImage(contentsOf: $0) }
        if let storeIcon { storeIcons[path] = storeIcon }
        let image = storeIcon ?? storeIcons[path] ?? NSWorkspace.shared.icon(forFile: path)
        image.size = NSSize(width: 128, height: 128)
        cache[path] = image
        return image
    }

    func icon(path: String) -> NSImage {
        if let image = cache[path] { return image }
        // Resolve symlinks (Safari) so the icon is the target app's, never a link icon.
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let image: NSImage
        if installGrace.contains(path), let fallback = installFallback(path: path, bundle: resolved) {
            image = fallback
        } else {
            let workspace = NSWorkspace.shared.icon(forFile: resolved.path)
            if storeIcons[path] != nil || installGrace.contains(path) {
                // Grace over: use the workspace icon unless it is still a blank tile.
                if looksBlank(workspace), let fallback = installFallback(path: path, bundle: resolved) {
                    image = fallback
                } else {
                    storeIcons[path] = nil
                    image = workspace
                }
            } else {
                image = workspace
            }
        }
        image.size = NSSize(width: 128, height: 128)
        cache[path] = image
        return image
    }

    // Freshly installed apps (call before the reload that first shows them).
    func beginInstallGrace(paths: [String]) {
        installGrace.formUnion(paths)
    }

    // LaunchServices had time to register them: trust the workspace icon again.
    func endInstallGrace(paths: [String]) {
        installGrace.subtract(paths)
    }

    // Store icon first (same look as during the download), else the bundle's own .icns.
    private func installFallback(path: String, bundle: URL) -> NSImage? {
        storeIcons[path] ?? Self.bundleIcon(bundle)
    }

    // Reads the icon file straight from the bundle (no LaunchServices, no Bundle cache).
    private static func bundleIcon(_ url: URL) -> NSImage? {
        let contents = url.appendingPathComponent("Contents")
        let plist = NSDictionary(contentsOf: contents.appendingPathComponent("Info.plist"))
        var names: [String] = []
        if let name = plist?["CFBundleIconFile"] as? String, !name.isEmpty { names.append(name) }
        names.append("AppIcon")
        let resources = contents.appendingPathComponent("Resources")
        for name in names {
            let file = name.hasSuffix(".icns") ? name : name + ".icns"
            if let image = NSImage(contentsOf: resources.appendingPathComponent(file)), image.isValid {
                return image
            }
        }
        return nil
    }

    // MARK: - Blank icon detection

    private static let signatureSide = 32

    // Generic app / folder icon, or a colorless near-white tile (the dashed placeholder).
    private func looksBlank(_ image: NSImage) -> Bool {
        guard let sig = Self.signature(image) else { return true }
        let generic = genericSignatures.contains { generic in
            var diff = 0
            for i in 0..<sig.count { diff += abs(Int(sig[i]) - Int(generic[i])) }
            return diff / sig.count < 4   // mean per-channel difference
        }
        return generic || Self.isColorlessLight(sig)
    }

    // Opaque pixels almost gray and mostly light, or nearly nothing drawn at all.
    private static func isColorlessLight(_ sig: [UInt8]) -> Bool {
        var opaque = 0, light = 0, maxSpread = 0
        for i in stride(from: 0, to: sig.count, by: 4) {
            let a = Int(sig[i + 3])
            guard a > 128 else { continue }
            // Un-premultiply roughly before comparing channels.
            let r = Int(sig[i]) * 255 / a, g = Int(sig[i + 1]) * 255 / a, b = Int(sig[i + 2]) * 255 / a
            opaque += 1
            maxSpread = max(maxSpread, max(r, g, b) - min(r, g, b))
            if r + g + b > 3 * 200 { light += 1 }
        }
        guard opaque > sig.count / 4 / 10 else { return true }
        return maxSpread < 24 && light * 10 >= opaque * 8
    }

    // Small RGBA render used to compare icons.
    private static func signature(_ image: NSImage) -> [UInt8]? {
        let side = signatureSide
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? bytes : nil
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
