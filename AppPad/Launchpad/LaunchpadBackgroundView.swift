import AppKit
import Accelerate
import ImageIO
import QuartzCore

nonisolated struct BlurredImage: @unchecked Sendable {
    let image: CGImage
}

// Process-wide blurred-wallpaper cache, shared by the Launchpad and Clipboard panels.
// Prewarmed at launch and refreshed on screen / Space / wake / app-switch changes,
// so showing a panel never has to blur the wallpaper on the spot.
@MainActor
final class WallpaperBlurCache: NSObject {
    static let shared = WallpaperBlurCache()

    // Path + modification date: same-path replacements still invalidate.
    struct Key: Hashable {
        let path: String
        let modified: Date?
    }

    enum Lookup {
        case noWallpaper
        case ready(CGImage)
        case pending(Key, URL)
    }

    private static let maxEntries = 4

    private var images: [Key: CGImage] = [:]
    private var order: [Key] = []   // oldest first
    private var loads: [Key: Task<CGImage?, Never>] = [:]
    private var isObserving = false
    private var refreshTask: Task<Void, Never>?

    // Begin observing and blur every screen's wallpaper in the background.
    func start() {
        if !isObserving {
            isObserving = true
            let center = NotificationCenter.default
            let workspace = NSWorkspace.shared.notificationCenter
            center.addObserver(self, selector: #selector(environmentChanged),
                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
            workspace.addObserver(self, selector: #selector(environmentChanged),
                                  name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            workspace.addObserver(self, selector: #selector(environmentChanged),
                                  name: NSWorkspace.didWakeNotification, object: nil)
            // Wallpaper changes have no public notification; leaving System Settings activates another app.
            workspace.addObserver(self, selector: #selector(environmentChanged),
                                  name: NSWorkspace.didActivateApplicationNotification, object: nil)
        }
        prewarmAllScreens()
    }

    func lookup(for screen: NSScreen) -> Lookup {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return .noWallpaper }
        let key = Self.key(for: url)
        if let image = images[key] { return .ready(image) }
        return .pending(key, url)
    }

    // Cached image, or the (shared, de-duplicated) background load.
    func image(for screen: NSScreen) async -> CGImage? {
        switch lookup(for: screen) {
        case .noWallpaper: return nil
        case .ready(let image): return image
        case .pending(let key, let url): return await load(key: key, url: url)
        }
    }

    private func load(key: Key, url: URL) async -> CGImage? {
        if let image = images[key] { return image }
        let task: Task<CGImage?, Never>
        if let existing = loads[key] {
            task = existing
        } else {
            task = Task {
                // Utility QoS: ImageIO/vImage may wait on default-QoS workers; a lower caller QoS avoids inversion.
                let result = await Task.detached(priority: .utility) {
                    WallpaperBlurCache.makeBlurred(url: url).map { BlurredImage(image: $0) }
                }.value
                return result?.image
            }
            loads[key] = task
        }
        let image = await task.value
        loads[key] = nil
        if let image { store(image, for: key) }
        return image
    }

    private func store(_ image: CGImage, for key: Key) {
        if images[key] == nil { order.append(key) }
        images[key] = image
        while order.count > Self.maxEntries {
            images[order.removeFirst()] = nil
        }
    }

    private func prewarmAllScreens() {
        for screen in NSScreen.screens {
            guard case .pending(let key, let url) = lookup(for: screen) else { continue }
            Task { _ = await self.load(key: key, url: url) }
        }
    }

    // Debounced: Space swipes and app switches can arrive in bursts.
    @objc private func environmentChanged() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.prewarmAllScreens()
        }
    }

    private static func key(for url: URL) -> Key {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return Key(path: url.path, modified: attrs?[.modificationDate] as? Date)
    }

    // Small thumbnail + two tent passes (≈ Gaussian). Runs entirely on the calling thread.
    nonisolated static func makeBlurred(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let format = vImage_CGImageFormat(
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  colorSpace: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue))
        else { return nil }

        do {
            var src = try vImage_Buffer(cgImage: thumbnail, format: format)
            var dst = try vImage_Buffer(width: Int(src.width), height: Int(src.height), bitsPerPixel: 32)
            defer {
                src.free()
                dst.free()
            }
            let kernel: UInt32 = 31   // must be odd
            let flags = vImage_Flags(kvImageEdgeExtend | kvImageDoNotTile)
            for _ in 0..<2 {
                guard vImageTentConvolve_ARGB8888(&src, &dst, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError,
                      vImageTentConvolve_ARGB8888(&dst, &src, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError
                else { return nil }
            }
            return try src.createCGImage(format: format)
        } catch {
            return nil
        }
    }
}

// Panel background.
// .wallpaper: the desktop picture slice under the panel, pre-blurred with vImage, then covered by the
//             system full-screen material (blendingMode .withinWindow) — Apple's own blur, tint and
//             noise, which avoids the banding/muddiness of a plain Gaussian blur.
// .white:     plain white.
final class LaunchpadBackgroundView: NSView {
    private let imageHost = NSView()
    private let imageLayer = CALayer()
    private let material = NSVisualEffectView()
    // Second pass of the same material: the "outside an open folder" look (clipboard option).
    private let extraBlur = NSVisualEffectView()
    // Latest wallpaper request; stale async results are dropped.
    private var requestID = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        imageHost.wantsLayer = true
        imageHost.autoresizingMask = [.width, .height]
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.actions = ["contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull()]
        imageHost.layer?.addSublayer(imageLayer)
        addSubview(imageHost)

        material.material = .fullScreenUI
        material.state = .active
        material.autoresizingMask = [.width, .height]
        addSubview(material)

        extraBlur.material = .fullScreenUI
        extraBlur.blendingMode = .withinWindow
        extraBlur.state = .active
        extraBlur.autoresizingMask = [.width, .height]
        extraBlur.isHidden = true
        addSubview(extraBlur)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageHost.frame = bounds
        imageLayer.frame = imageHost.bounds
        material.frame = bounds
        extraBlur.frame = bounds
    }

    func update(style: PanelBackgroundStyle, screen: NSScreen, panelFrame: NSRect, heavyBlur: Bool = false) {
        requestID += 1
        extraBlur.isHidden = !(heavyBlur && style == .wallpaper)
        switch style {
        case .white:
            imageHost.isHidden = true
            material.isHidden = true
            layer?.backgroundColor = NSColor.white.cgColor
        case .wallpaper:
            layer?.backgroundColor = NSColor.black.cgColor
            material.isHidden = false
            showWallpaper(screen: screen, panelFrame: panelFrame)
        }
    }

    // Plain color (clipboard panel options).
    func update(solid color: NSColor) {
        requestID += 1
        imageHost.isHidden = true
        material.isHidden = true
        extraBlur.isHidden = true
        layer?.backgroundColor = color.cgColor
    }

    private func showWallpaper(screen: NSScreen, panelFrame: NSRect) {
        let cache = WallpaperBlurCache.shared
        switch cache.lookup(for: screen) {
        case .noWallpaper:
            showMaterialOnly()
        case .ready(let image):
            apply(image, screen: screen, panelFrame: panelFrame)   // normal path: prewarmed
        case .pending:
            // Cache miss (e.g. wallpaper just changed): material now, image when ready.
            showMaterialOnly()
            let id = requestID
            Task { [weak self] in
                let image = await cache.image(for: screen)
                guard let self, id == self.requestID, let image else { return }
                self.apply(image, screen: screen, panelFrame: panelFrame)
            }
        }
    }

    // No wallpaper image: blur whatever is behind the window instead.
    private func showMaterialOnly() {
        imageHost.isHidden = true
        material.blendingMode = .behindWindow
    }

    // Wallpaper is aspect-filled to the screen; show the slice under the panel.
    private func apply(_ image: CGImage, screen: NSScreen, panelFrame: NSRect) {
        imageHost.isHidden = false
        material.blendingMode = .withinWindow
        let screenFrame = screen.frame
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = max(screenFrame.width / imageSize.width, screenFrame.height / imageSize.height)
        let filled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (filled.width - screenFrame.width) / 2
        let offsetY = (filled.height - screenFrame.height) / 2
        let x = (panelFrame.minX - screenFrame.minX + offsetX) / filled.width
        let y = (panelFrame.minY - screenFrame.minY + offsetY) / filled.height
        imageLayer.contents = image
        imageLayer.contentsRect = CGRect(x: x, y: y,
                                         width: panelFrame.width / filled.width,
                                         height: panelFrame.height / filled.height)
    }
}
