import AppKit
import Accelerate
import ImageIO
import QuartzCore

// Blur strength + internal saturation; part of the cache key.
nonisolated struct WallpaperBlurParams: Hashable, Sendable {
    let level: Int        // 0…20 (blur 0…1 in 5% steps)
    let saturation: Int   // percent, 100 = unchanged
}

nonisolated struct BlurredWallpaper: @unchecked Sendable {
    let image: CGImage
    let luminance: Double   // average, 0…1 (picks light / dark text)
}

// Process-wide blurred-wallpaper cache, shared by the Launchpad, Clipboard and Workflow panels.
// Prewarmed at launch for the blur levels in use and refreshed on screen / Space / wake /
// app-switch / theme changes, so showing a panel never has to blur the wallpaper on the spot.
@MainActor
final class WallpaperBlurCache: NSObject {
    static let shared = WallpaperBlurCache()

    // Path + modification date (same-path replacements still invalidate) + blur params.
    struct Key: Hashable {
        let path: String
        let modified: Date?
        let params: WallpaperBlurParams
    }

    enum Lookup {
        case noWallpaper
        case ready(BlurredWallpaper)
        case pending(Key, URL)
    }

    // Up to three panels × a couple of displays.
    private static let maxEntries = 8

    private var entries: [Key: BlurredWallpaper] = [:]
    private var order: [Key] = []   // oldest first
    private var loads: [Key: Task<BlurredWallpaper?, Never>] = [:]
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
        prewarm()
    }

    func lookup(for screen: NSScreen, params: WallpaperBlurParams) -> Lookup {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return .noWallpaper }
        let key = Self.key(for: url, params: params)
        if let entry = entries[key] { return .ready(entry) }
        return .pending(key, url)
    }

    // Cached image, or the (shared, de-duplicated) background load.
    func image(for screen: NSScreen, params: WallpaperBlurParams) async -> BlurredWallpaper? {
        switch lookup(for: screen, params: params) {
        case .noWallpaper: return nil
        case .ready(let entry): return entry
        case .pending(let key, let url): return await load(key: key, url: url)
        }
    }

    // Blur every screen for the params the panels currently use (current theme).
    func prewarm() {
        let specs = [BackgroundSurface.launchpad, .clipboard, .workflows].map { PanelBackgroundSpec.current(for: $0) }
        let params = Set(specs.filter { $0.needsWallpaper }.map { $0.blurParams })
        for screen in NSScreen.screens {
            for p in params {
                guard case .pending(let key, let url) = lookup(for: screen, params: p) else { continue }
                Task { _ = await self.load(key: key, url: url) }
            }
        }
    }

    private func load(key: Key, url: URL) async -> BlurredWallpaper? {
        if let entry = entries[key] { return entry }
        let task: Task<BlurredWallpaper?, Never>
        if let existing = loads[key] {
            task = existing
        } else {
            let params = key.params
            task = Task {
                // Utility QoS: ImageIO/vImage may wait on default-QoS workers; a lower caller QoS avoids inversion.
                await Task.detached(priority: .utility) {
                    WallpaperBlurCache.makeBlurred(url: url, params: params)
                }.value
            }
            loads[key] = task
        }
        let entry = await task.value
        loads[key] = nil
        if let entry { store(entry, for: key) }
        return entry
    }

    private func store(_ entry: BlurredWallpaper, for key: Key) {
        if entries[key] == nil { order.append(key) }
        entries[key] = entry
        while order.count > Self.maxEntries {
            entries[order.removeFirst()] = nil
        }
    }

    // Debounced: Space swipes and app switches can arrive in bursts.
    @objc private func environmentChanged() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.prewarm()
        }
    }

    private static func key(for url: URL, params: WallpaperBlurParams) -> Key {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return Key(path: url.path, modified: attrs?[.modificationDate] as? Date, params: params)
    }

    // Thumbnail (larger when barely blurred) + two tent passes (≈ Gaussian) + saturation + dither.
    // Runs entirely on the calling thread.
    nonisolated static func makeBlurred(url: URL, params: WallpaperBlurParams) -> BlurredWallpaper? {
        let level = min(max(params.level, 0), 20)
        // Sharp wallpaper needs real resolution; strong blur is fine from a small thumbnail.
        let maxPixel = level == 0 ? 3200 : (level <= 3 ? 1600 : 720)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
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
            let flags = vImage_Flags(kvImageEdgeExtend | kvImageDoNotTile)
            if level > 0 {
                // Radius scales with the thumbnail so a level looks the same at any size.
                let scale = Double(maxPixel) / 720
                let radius = Int((Double(level) / 20 * 30 * scale).rounded())
                let kernel = UInt32(max(radius, 1) * 2 + 1)   // must be odd
                for _ in 0..<2 {
                    guard vImageTentConvolve_ARGB8888(&src, &dst, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError,
                          vImageTentConvolve_ARGB8888(&dst, &src, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError
                    else { return nil }
                }
            }
            if params.saturation != 100 {
                var matrix = saturationMatrix(Double(params.saturation) / 100)
                guard vImageMatrixMultiply_ARGB8888(&src, &dst, &matrix, 256, nil, nil, vImage_Flags(kvImageNoFlags)) == kvImageNoError
                else { return nil }
                swap(&src, &dst)
            }
            if level >= 2 { dither(&src) }   // smooth gradients band without it
            let luminance = averageLuminance(src)
            return BlurredWallpaper(image: try src.createCGImage(format: format), luminance: luminance)
        } catch {
            return nil
        }
    }

    // Row-vector ARGB matrix (dest = src × M), Rec. 709 weights, scaled by 256.
    nonisolated private static func saturationMatrix(_ s: Double) -> [Int16] {
        let lr = 0.2126 * (1 - s), lg = 0.7152 * (1 - s), lb = 0.0722 * (1 - s)
        let m: [Double] = [
            1, 0, 0, 0,                 // A
            0, lr + s, lr, lr,          // R
            0, lg, lg + s, lg,          // G
            0, lb, lb, lb + s,          // B
        ]
        return m.map { Int16(($0 * 256).rounded()) }
    }

    // ±1 triangular noise on RGB (alpha is opaque for wallpapers).
    nonisolated private static func dither(_ buffer: inout vImage_Buffer) {
        guard let base = buffer.data?.assumingMemoryBound(to: UInt8.self) else { return }
        var seed: UInt32 = 0x9E37_79B9
        for y in 0..<Int(buffer.height) {
            let row = base + y * buffer.rowBytes
            for x in 0..<Int(buffer.width) {
                let p = row + x * 4
                for c in 1...3 {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    let noise = Int((seed >> 24) & 0x3) - Int((seed >> 26) & 0x3)   // -3…3, peaked at 0
                    let value = Int(p[c]) + noise / 2
                    p[c] = UInt8(clamping: value)
                }
            }
        }
    }

    // Sampled average (gamma-encoded, same scale as ClipboardColors.isDark).
    nonisolated private static func averageLuminance(_ buffer: vImage_Buffer) -> Double {
        guard let base = buffer.data?.assumingMemoryBound(to: UInt8.self) else { return 0.5 }
        let step = 8
        var sum = 0.0
        var count = 0
        for y in stride(from: 0, to: Int(buffer.height), by: step) {
            let row = base + y * buffer.rowBytes
            for x in stride(from: 0, to: Int(buffer.width), by: step) {
                let p = row + x * 4
                sum += 0.2126 * Double(p[1]) + 0.7152 * Double(p[2]) + 0.0722 * Double(p[3])
                count += 1
            }
        }
        return count == 0 ? 0.5 : sum / Double(count) / 255
    }
}

// One panel's background resolved for the current theme.
// wallpaper: blurred wallpaper image + black veil at `opacity` (lighter default in the light theme).
// colors:    color at `opacity` over the live windows behind the panel, blurred by `blur`.
struct PanelBackgroundSpec {
    let style: BackgroundStyle
    let variant: ThemeVariant
    let blur: Double
    let opacity: Double
    let saturation: Double
    let overlay: NSColor   // drawn at `opacity` on top

    var blurParams: WallpaperBlurParams {
        WallpaperBlurParams(level: Int((blur * 20).rounded()),
                            saturation: Int((saturation * 100).rounded()))
    }

    private var isTranslucent: Bool { opacity < 0.995 }

    // Wallpaper style, not fully covered by its veil.
    var needsWallpaper: Bool { style == .wallpaper && isTranslucent }

    // Color styles below 100%: the windows behind the panel show through.
    var showsWindowsBehind: Bool { style != .wallpaper && isTranslucent }

    // Window-server blur radius (pt). Quadratic: fine steps at the low end, where blur changes most.
    static let maxBehindBlurRadius: Double = 64
    var behindBlurRadius: Int { Int((blur * blur * Self.maxBehindBlurRadius).rounded()) }

    // Fallback without the window-server call: system blur (fixed radius) faded in, 0…1.
    var behindBlurAmount: CGFloat { CGFloat(blur) }

    // Theme side in effect: NSApp.appearance is nil (system), aqua or darkAqua (General › Theme).
    @MainActor static var currentVariant: ThemeVariant {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    @MainActor static func current(for surface: BackgroundSurface) -> PanelBackgroundSpec {
        let settings = Preferences.shared.effectiveBackground(for: surface)
        let variant = currentVariant
        let tuning = settings.tuning(settings.style, variant)
        let overlay: NSColor
        if let hex = settings.colorHex(settings.style, variant) {
            overlay = ClipboardColors.color(hex: hex) ?? .gray
        } else {
            overlay = .black   // wallpaper veil; the theme only changes its strength
        }
        return PanelBackgroundSpec(style: settings.style, variant: variant,
                                   blur: min(max(tuning.blur, 0), 1),
                                   opacity: min(max(tuning.opacity, 0), 1),
                                   saturation: BackgroundPalette.saturation(settings.style),
                                   overlay: overlay)
    }

    // Brightness of the composed background; unknown wallpaper / windows → a guess per theme.
    func luminance(wallpaper: Double?) -> Double {
        let c = overlay.usingColorSpace(.sRGB) ?? overlay
        let top = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        let base: Double
        if needsWallpaper {
            base = wallpaper ?? (variant == .dark ? 0.3 : 0.55)
        } else if showsWindowsBehind {
            base = variant == .dark ? 0.2 : 0.8   // app windows mostly follow the theme
        } else {
            return top
        }
        return base * (1 - opacity) + top * opacity
    }

    // Light background → aqua (dark text); dark background → darkAqua (white text).
    @MainActor func appearance(on screen: NSScreen?) -> NSAppearance? {
        var wallpaper: Double?
        if needsWallpaper, let screen,
           case .ready(let entry) = WallpaperBlurCache.shared.lookup(for: screen, params: blurParams) {
            wallpaper = entry.luminance
        }
        return NSAppearance(named: luminance(wallpaper: wallpaper) > 0.6 ? .aqua : .darkAqua)
    }
}

// Panel background.
// wallpaper: wallpaper slice under the panel (vImage blur + saturation), then the black veil at `opacity`.
//            Without a wallpaper image the behind-window blur stands in.
// colors:    0% transparency = plain color; above that the color sits over the live windows behind
//            the panel, blurred by the window server at the chosen radius (0 = sharp).
final class LaunchpadBackgroundView: NSView {
    private let imageHost = NSView()
    private let imageLayer = CALayer()
    private let material = NSVisualEffectView()
    private let tint = NSView()
    // Async wallpaper arrived (the owner re-picks light / dark text).
    var onWallpaperApplied: (() -> Void)?
    // Color layer over the live windows behind (not opaque): two of these stacked look brighter,
    // so PanelMorph cross-fades them instead of overlapping. overlayAlpha = that layer's alpha.
    private(set) var showsWindowsBehind = false
    private(set) var overlayAlpha: CGFloat = 1
    // Latest wallpaper request; stale async results are dropped.
    private var requestID = 0
    // How the shown wallpaper maps to screen points (for PanelMorph's moving slice).
    private struct SliceGeometry {
        let screenFrame: NSRect
        let filled: CGSize
        let offset: CGSize
        let panelFrame: NSRect
    }
    private var slice: SliceGeometry?
    private static let sliceKey = "morphSlice"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        imageHost.wantsLayer = true
        imageHost.autoresizingMask = [.width, .height]
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .linear
        imageLayer.actions = ["contents": NSNull(), "contentsRect": NSNull(), "bounds": NSNull(), "position": NSNull()]
        imageHost.layer?.addSublayer(imageLayer)
        imageHost.isHidden = true
        addSubview(imageHost)

        material.material = .fullScreenUI
        material.blendingMode = .behindWindow
        material.state = .active
        material.autoresizingMask = [.width, .height]
        material.isHidden = true
        addSubview(material)

        tint.wantsLayer = true
        tint.layer?.actions = ["backgroundColor": NSNull()]
        tint.autoresizingMask = [.width, .height]
        addSubview(tint)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        imageHost.frame = bounds
        imageLayer.frame = imageHost.bounds
        material.frame = bounds
        tint.frame = bounds
    }

    func update(spec: PanelBackgroundSpec, screen: NSScreen, panelFrame: NSRect) {
        requestID += 1
        let translucent = spec.needsWallpaper || spec.showsWindowsBehind
        tint.layer?.backgroundColor = spec.overlay.withAlphaComponent(translucent ? spec.opacity : 1).cgColor
        showsWindowsBehind = spec.showsWindowsBehind
        overlayAlpha = CGFloat(spec.opacity)
        let panel = window as? LaunchpadPanel
        if spec.showsWindowsBehind {
            // Live windows behind the (non-opaque) panel; no blur → just see-through.
            slice = nil
            imageHost.isHidden = true
            layer?.backgroundColor = NSColor.clear.cgColor
            if WindowBlur.isAvailable {
                material.isHidden = true
                panel?.behindBlurRadius = spec.behindBlurRadius
            } else {
                panel?.behindBlurRadius = 0
                material.isHidden = spec.behindBlurAmount < 0.005
                material.alphaValue = spec.behindBlurAmount
            }
            return
        }
        panel?.behindBlurRadius = 0
        guard spec.needsWallpaper else {
            // Solid color (or veil at 100%): nothing underneath.
            slice = nil
            imageHost.isHidden = true
            material.isHidden = true
            return
        }
        let cache = WallpaperBlurCache.shared
        let params = spec.blurParams
        switch cache.lookup(for: screen, params: params) {
        case .noWallpaper:
            showMaterialOnly()
        case .ready(let entry):
            apply(entry.image, screen: screen, panelFrame: panelFrame)   // normal path: prewarmed
        case .pending:
            // Cache miss (wallpaper or blur just changed): keep the current image if any, swap when ready.
            if imageHost.isHidden { showMaterialOnly() }
            let id = requestID
            Task { [weak self] in
                let entry = await cache.image(for: screen, params: params)
                guard let self, id == self.requestID, let entry else { return }
                self.apply(entry.image, screen: screen, panelFrame: panelFrame)
                self.onWallpaperApplied?()
            }
        }
    }

    // No wallpaper image: blur whatever is behind the window instead.
    private func showMaterialOnly() {
        slice = nil
        imageHost.isHidden = true
        material.isHidden = false
        material.alphaValue = 1
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    // Wallpaper is aspect-filled to the screen; show the slice under the panel.
    private func apply(_ image: CGImage, screen: NSScreen, panelFrame: NSRect) {
        imageHost.isHidden = false
        material.isHidden = true
        layer?.backgroundColor = NSColor.black.cgColor
        let screenFrame = screen.frame
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = max(screenFrame.width / imageSize.width, screenFrame.height / imageSize.height)
        let filled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offsetX = (filled.width - screenFrame.width) / 2
        let offsetY = (filled.height - screenFrame.height) / 2
        let geometry = SliceGeometry(screenFrame: screenFrame, filled: filled,
                                     offset: CGSize(width: offsetX, height: offsetY), panelFrame: panelFrame)
        slice = geometry
        imageLayer.removeAnimation(forKey: Self.sliceKey)
        imageLayer.contents = image
        imageLayer.contentsRect = Self.contentsRect(for: panelFrame, geometry)
    }

    private static func contentsRect(for rect: NSRect, _ g: SliceGeometry) -> CGRect {
        CGRect(x: (rect.minX - g.screenFrame.minX + g.offset.width) / g.filled.width,
               y: (rect.minY - g.screenFrame.minY + g.offset.height) / g.filled.height,
               width: rect.width / g.filled.width,
               height: rect.height / g.filled.height)
    }

    // PanelMorph: while the panel is scaled onto `rect` (screen points), show the wallpaper under `rect`,
    // so the blur stays put instead of shrinking with the panel. nil = back to the panel's own frame.
    // Animated with the same duration / curve as the scale, so both stay in step.
    func setWallpaperSlice(onScreen rect: NSRect?, duration: TimeInterval?, timing: CAMediaTimingFunction? = nil) {
        guard let slice, !imageHost.isHidden else { return }
        let target = Self.contentsRect(for: rect ?? slice.panelFrame, slice)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let duration {
            let animation = CABasicAnimation(keyPath: "contentsRect")
            animation.fromValue = NSValue(rect: imageLayer.presentation()?.contentsRect ?? imageLayer.contentsRect)
            animation.toValue = NSValue(rect: target)
            animation.duration = duration
            animation.timingFunction = timing ?? CAMediaTimingFunction(name: .easeOut)
            imageLayer.add(animation, forKey: Self.sliceKey)
        } else {
            imageLayer.removeAnimation(forKey: Self.sliceKey)
        }
        imageLayer.contentsRect = target
        CATransaction.commit()
    }
}
