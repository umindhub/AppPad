import AppKit
import Darwin

// Window-server blur of whatever is behind a window, at any radius (private CGS call, as iTerm2 does).
// Resolved with dlsym, so a missing symbol only disables it (callers fall back to the system material).
enum WindowBlur {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SetRadiusFn = @convention(c) (Int32, Int32, Int32) -> Int32

    private static let connection: ConnectionFn? = symbol("CGSDefaultConnectionForThread")
    private static let setRadius: SetRadiusFn? = symbol("CGSSetWindowBackgroundBlurRadius")

    static var isAvailable: Bool { connection != nil && setRadius != nil }

    private static func symbol<T>(_ name: String) -> T? {
        // RTLD_DEFAULT: search every loaded image (SkyLight is loaded by AppKit).
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    @discardableResult
    static func set(_ window: NSWindow, radius: Int) -> Bool {
        guard window.windowNumber > 0, let connection, let setRadius else { return false }
        return setRadius(connection(), Int32(truncatingIfNeeded: window.windowNumber), Int32(max(radius, 0))) == 0
    }
}

// Borderless, non-activating floating panel (Spotlight style):
// it takes keyboard focus without activating AppPad, so the hotkey works from any app
// and closing it leaves the previous app frontmost.
final class LaunchpadPanel: NSPanel {
    // Launchpad covering the menu bar (above the menu bar and status items).
    static let aboveMenuBarLevel = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)

    var keyHandler: ((NSEvent) -> Bool)?
    // Sees every keyDown before the field editor (Workflow panel: ⌥ / ⌃ in-panel shortcuts).
    var keyDownHandler: ((NSEvent) -> Bool)?
    // Sees modifier / key / click events without consuming them (Launchpad: hold ⌥ for edit mode).
    var eventObserver: ((NSEvent) -> Void)?
    // Set by the owning controller: the two layers PanelMorph fades / re-slices separately.
    weak var morphBackground: LaunchpadBackgroundView?
    weak var morphContent: NSView?

    // MARK: - Behind-window blur (color backgrounds)
    // Drawn by PanelBackdrop's helper window right below the panel, never by the panel itself:
    // a panel switch then only moves / resizes that one window and the blur never toggles.

    // Window-server blur radius for what is behind the panel; 0 = off. Set by LaunchpadBackgroundView.
    var behindBlurRadius = 0 {
        didSet { if behindBlurRadius != oldValue { PanelBackdrop.shared.update(for: self) } }
    }
    // Rounded corners of that blur (matches the content); set by the controllers' applyFrame.
    var cornerMaskRadius: CGFloat = 0 {
        didSet {
            guard cornerMaskRadius != oldValue else { return }
            PanelBackdrop.shared.update(for: self)
            PanelShadow.shared.update(for: self)
        }
    }

    // Drop shadow, drawn by PanelShadow's helper window (cut out under the panel). The window-server
    // shadow stays off: it also shows through a translucent background and darkens it.
    var dropsShadow = true {
        didSet { if dropsShadow != oldValue { PanelShadow.shared.update(for: self) } }
    }

    // Blur scaled by window alpha (fade in / out, invisible warm-up).
    // KVO, not an alphaValue override: animator() calls the setter on its proxy, which crashes
    // a Swift override that touches stored properties.
    private var alphaObservation: NSKeyValueObservation?

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        if place == .out {
            PanelBackdrop.shared.panelDidHide(self)
            PanelShadow.shared.panelDidHide(self)
        } else {
            PanelBackdrop.shared.update(for: self)
            PanelShadow.shared.update(for: self)
        }
    }

    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(frameRect, display: flag)
        PanelBackdrop.shared.update(for: self)
        PanelShadow.shared.update(for: self)
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style.union(.nonactivatingPanel), backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false   // see dropsShadow
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Belongs to the Space it opens on (slides away with it on a Space switch, like the
        // macOS 15 Launchpad); each show moves it to the current Space. Also over full-screen apps.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        alphaObservation = observe(\.alphaValue, options: [.new]) { panel, _ in
            MainActor.assumeIsolated {   // window alpha only changes on the main thread
                if panel.behindBlurRadius > 0 { PanelBackdrop.shared.update(for: panel) }
                if panel.dropsShadow { PanelShadow.shared.update(for: panel) }
            }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Replayed trackpad taps
    // A tap that stops a running swipe is eaten by macOS (no click). The controller replays it
    // here; whichever of the replay / a real click comes second is dropped, so it acts once.

    private static let replayWindow: TimeInterval = 0.35
    private(set) var lastRealMouseDown: TimeInterval = -1
    private var lastReplay: TimeInterval = -1
    private var dropNextMouseUp = false
    private var isReplaying = false

    override func sendEvent(_ event: NSEvent) {
        if let eventObserver {
            switch event.type {
            case .flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
                eventObserver(event)
            default:
                break
            }
        }
        if event.type == .keyDown, let keyDownHandler, keyDownHandler(event) { return }
        if !isReplaying {
            switch event.type {
            case .leftMouseDown:
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastReplay < Self.replayWindow {
                    dropNextMouseUp = true
                    return
                }
                lastRealMouseDown = now
            case .leftMouseUp where dropNextMouseUp:
                dropNextMouseUp = false
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    // Synthesized single click (down + up) at a window point.
    func replayClick(atWindowPoint point: NSPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRealMouseDown >= Self.replayWindow else { return }   // real click already came
        lastReplay = now
        isReplaying = true
        defer { isReplaying = false }
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            guard isVisible,
                  let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                                 timestamp: now, windowNumber: windowNumber, context: nil,
                                                 eventNumber: 0, clickCount: 1,
                                                 pressure: type == .leftMouseDown ? 1 : 0)
            else { return }
            sendEvent(event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        // AppPad is not the active app, so route standard edit shortcuts ourselves.
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if let key = event.charactersIgnoringModifiers?.lowercased(), flags.contains(.command) {
            let action: Selector?
            switch (key, flags) {
            case ("x", .command): action = #selector(NSText.cut(_:))
            case ("c", .command): action = #selector(NSText.copy(_:))
            case ("v", .command): action = #selector(NSText.paste(_:))
            case ("a", .command): action = #selector(NSText.selectAll(_:))
            case ("z", .command): action = Selector(("undo:"))
            case ("z", [.command, .shift]): action = Selector(("redo:"))
            default: action = nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// Flipped container helper (top-left origin).
class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// Click on empty space: fires on mouse up if not moved and released within 0.5 s.
// Empty space never starts edit mode (only a long press on an app icon does).
final class BackgroundPressTracker {
    var onClick: (() -> Void)?

    private static let maxClickDuration: TimeInterval = 0.5

    private var start: NSPoint = .zero
    private var downTime: TimeInterval = 0
    private var isActive = false

    func mouseDown(_ event: NSEvent) {
        isActive = true
        start = event.locationInWindow
        downTime = event.timestamp
    }

    func mouseDragged(_ event: NSEvent) {
        let dx = event.locationInWindow.x - start.x
        let dy = event.locationInWindow.y - start.y
        if dx * dx + dy * dy > 25 { isActive = false }
    }

    func mouseUp(_ event: NSEvent) {
        defer { isActive = false }
        guard isActive, event.timestamp - downTime <= Self.maxClickDuration else { return }
        onClick?()
    }
}

// Root content view: forwards stray scroll events to the pager, Esc when no field is focused,
// and clicks on empty space.
final class LaunchpadRootView: FlippedView {
    var onScroll: ((NSEvent) -> Void)?
    var onEscape: (() -> Void)?
    let press = BackgroundPressTracker()

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event)
    }

    override func mouseDown(with event: NSEvent) { press.mouseDown(event) }
    override func mouseDragged(with event: NSEvent) { press.mouseDragged(event) }
    override func mouseUp(with event: NSEvent) { press.mouseUp(event) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Panel switch (⌘⇧J / ⌘⇧K)
// Gap-free hand-over: the outgoing panel stays on screen until the incoming one is drawn
// on top of it, then orders out.
// Same size (Clipboard ⇄ Workflows): incoming opaque at once, old one leaves on the next run-loop turn.
// The old panel's content view is hidden in that same screen update: two translucent backgrounds
// stacked (and the old rows showing through) flashed for a frame.
// Different size (Launchpad ⇄ Clipboard / Workflows): PanelMorph expands / shrinks between the two
// frames, contents swap at the halfway point, then the old one leaves.
// (Hiding first and fading in from alpha 0 briefly showed the desktop → flash.)
@MainActor
enum PanelSwitch {
    private static var outgoing: NSWindow?
    private static var hideOutgoing: (() -> Void)?
    private static var morph: PanelMorph?
    private static var hiddenContent: NSView?   // outgoing content view hidden for a same-size hand-over
    private static var token = 0
    private static let fallbackDelay: TimeInterval = 0.3

    // Outgoing panel: call instead of hide(), then ask for the next panel.
    static func begin(from window: NSWindow, hide: @escaping () -> Void) {
        finish()
        token += 1
        let current = token
        outgoing = window
        hideOutgoing = hide
        // Next panel never showed (e.g. unavailable): close anyway.
        DispatchQueue.main.asyncAfter(deadline: .now() + fallbackDelay) {
            if current == token { finish() }
        }
    }

    // Outgoing panel ignores its own resign-key while handing over.
    static func isOutgoing(_ window: NSWindow) -> Bool {
        outgoing === window
    }

    // Incoming panel, before ordering in: true → hand-over (alpha from incomingAlpha, no own fade).
    // Switching to the same panel just cancels the hand-over.
    static func prepareIncoming(_ window: NSWindow) -> Bool {
        guard let outgoing else { return false }
        if outgoing === window {
            token += 1
            let pending = morph
            morph = nil
            self.outgoing = nil
            hideOutgoing = nil
            pending?.settleIncoming()
            pending?.resetOutgoing()
            restoreContent()
            return false
        }
        return true
    }

    // Incoming panel during a hand-over, after its frame is set and before ordering in:
    // the alpha to order in with (0 = morph starts transparent, 1 = instant hand-over).
    static func incomingAlpha(for window: NSWindow) -> CGFloat {
        morph = nil
        guard let outgoing, outgoing !== window else { return 1 }
        guard let plan = PanelMorph(from: outgoing, to: window) else {
            hideContent(of: outgoing, under: window)
            return 1
        }
        morph = plan
        plan.prepare()
        return 0
    }

    // Same-size hand-over: only the incoming panel shows from its first frame on.
    // Blur and shadow live in their own helper windows, so they are not affected.
    private static func hideContent(of outgoing: NSWindow, under incoming: NSWindow) {
        guard let content = outgoing.contentView else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.isHidden = true
        CATransaction.commit()
        hiddenContent = content
    }

    // After the outgoing panel ordered out (or the switch went back to it).
    private static func restoreContent() {
        hiddenContent?.isHidden = false
        hiddenContent = nil
    }

    // Incoming panel, right after makeKeyAndOrderFront.
    // afterHandOff runs once the old panel is gone (keeps input restore → switch order).
    static func takeOver(_ window: NSWindow, afterHandOff: @escaping () -> Void = {}) {
        token += 1
        let current = token
        // Commit the new panel's first frame before the old one leaves / the morph starts.
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        let plan = morph?.incoming === window ? morph : nil
        DispatchQueue.main.async {
            guard current == token else { return }
            guard let plan else {
                finish()
                afterHandOff()
                return
            }
            plan.run {
                guard current == token else { return }
                finish()
                afterHandOff()
            }
        }
    }

    // Also cuts a running morph short: incoming snaps to its final look, outgoing hides.
    private static func finish() {
        let hide = hideOutgoing
        let pending = morph
        outgoing = nil
        hideOutgoing = nil
        morph = nil
        pending?.settleIncoming()
        hide?()
        pending?.resetOutgoing()
        restoreContent()
    }
}

// MARK: - Panel morph
// Launchpad ⇄ Clipboard / Workflows (different size; centers may differ, e.g. Launchpad covering
// the menu bar). The larger panel's frame (content layer scale + move + corner radius) goes between
// its own frame and the smaller one's,
// its wallpaper slice follows so the blur always matches what is under it.
// Both contents scale uniformly with that frame: Launchpad's icons shrink into the panel's frame,
// the panel's content comes in from Launchpad size (or leaves growing to it). To draw that without
// clipping, the smaller panel's window spans the large frame during the morph, its views centered.
// Content never overlaps: one panel's content fades out, then the other's fades in.
// The smaller panel sits above the larger one the whole time, its background only shows while the
// frames (nearly) coincide: last quarter when shrinking, first quarter when expanding.
//   shrink (Launchpad → panel): icons out [0, ⅔], panel content in [⅔, 1], panel background in [¾, 1]
//   expand (panel → Launchpad): panel content out [0, ⅓], panel background out [0, ¼], icons in [⅓, 1]
// Shadow: PanelShadow's window spans the large frame during the morph; its cut-out shadow follows
// the visible frame (same curve) and fades between the two panels' shadow states.
@MainActor
final class PanelMorph {
    private static let duration: TimeInterval = 0.5
    // Content hand-over point (fraction of duration).
    private static let shrinkSwap: Double = 2.0 / 3
    private static let expandSwap: Double = 1.0 / 3
    // Shrink keeps moving late (panel content still visibly shrinking after ⅔);
    // expand moves early (panel content visibly growing before ⅓).
    private static let shrinkCurve = CAMediaTimingFunction(controlPoints: 0.42, 0, 0.58, 1)
    private static let expandCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
    private static let transformKey = "panelMorph"
    private static let radiusKey = "panelMorphRadius"
    private static let fadeKey = "panelMorphFade"
    private static let contentKey = "panelMorphContent"
    private static let backgroundKey = "panelMorphBackground"
    private static let backgroundRadiusKey = "panelMorphBackgroundRadius"

    let incoming: NSWindow
    let outgoing: NSWindow
    private let incomingIsLarge: Bool
    private let ratio: CGSize          // small frame / large frame
    private let smallFrame: NSRect
    private let largeFrame: NSRect
    private var smallWindowSpread = false
    private let incomingRadius: CGFloat
    private let outgoingRadius: CGFloat
    // Launchpad may sit above the menu bar: both panels share the higher level during the morph.
    private var incomingLevel: NSWindow.Level = .floating
    private var outgoingLevel: NSWindow.Level = .floating

    private struct Pose {
        let scale: CGSize
        let radius: CGFloat            // layer cornerRadius (before scaling)
        // Move after scaling, window points (y up): large panel's center → small frame's center.
        var offset = CGSize.zero
        // Extra scale on the content inside, so frame × content is uniform.
        var contentScale = CGSize(width: 1, height: 1)
    }

    private var large: NSWindow { incomingIsLarge ? incoming : outgoing }
    private var small: NSWindow { incomingIsLarge ? outgoing : incoming }
    private var largeRadius: CGFloat { incomingIsLarge ? incomingRadius : outgoingRadius }
    private var smallRadius: CGFloat { incomingIsLarge ? outgoingRadius : incomingRadius }

    // nil → plain hand-over (same size, or not the same display).
    init?(from outgoing: NSWindow, to incoming: NSWindow) {
        let a = outgoing.frame
        let b = incoming.frame
        guard outgoing.isVisible, a.width > 0, a.height > 0, b.width > 0, b.height > 0 else { return nil }
        let incomingIsLarge = b.width * b.height > a.width * a.height
        let largeFrame = incomingIsLarge ? b : a
        let smallFrame = incomingIsLarge ? a : b
        // Centers may differ (Launchpad covering the menu bar reaches higher); the small frame
        // only has to lie inside the large one.
        guard largeFrame.insetBy(dx: -4, dy: -4).contains(smallFrame) else { return nil }
        guard largeFrame.width - smallFrame.width > 24 || largeFrame.height - smallFrame.height > 24 else { return nil }
        self.incoming = incoming
        self.outgoing = outgoing
        self.incomingIsLarge = incomingIsLarge
        ratio = CGSize(width: min(1, smallFrame.width / largeFrame.width),
                       height: min(1, smallFrame.height / largeFrame.height))
        self.smallFrame = smallFrame
        self.largeFrame = largeFrame
        // Radii as set by each controller's applyFrame (filled 12 / floating 26).
        incomingRadius = incoming.contentView?.layer?.cornerRadius ?? LaunchpadController.cornerRadius
        outgoingRadius = outgoing.contentView?.layer?.cornerRadius ?? LaunchpadController.cornerRadius
    }

    // On screen a layer radius R shows as about R × scale, so the pose divides the wanted radius by its scale.
    private var largeAtSmall: Pose {
        let mean = (ratio.width * ratio.height).squareRoot()
        // Content: min(ratio) both ways, so it keeps its proportions and stays inside the frame.
        let uniform = min(ratio.width, ratio.height)
        return Pose(scale: ratio, radius: smallRadius / max(mean, 0.01),
                    offset: CGSize(width: smallFrame.midX - largeFrame.midX,
                                   height: smallFrame.midY - largeFrame.midY),
                    contentScale: CGSize(width: uniform / max(ratio.width, 0.01),
                                         height: uniform / max(ratio.height, 0.01)))
    }
    private var largeAtRest: Pose { Pose(scale: Self.identity, radius: largeRadius) }
    private static let identity = CGSize(width: 1, height: 1)
    // Small panel's content at the large frame: uniform, inside the large frame.
    private var smallContentAtLarge: CGSize {
        let grow = 1 / max(ratio.width, ratio.height, 0.01)
        return CGSize(width: grow, height: grow)
    }

    private static func parts(_ window: NSWindow) -> (background: LaunchpadBackgroundView?, content: NSView?) {
        let panel = window as? LaunchpadPanel
        return (panel?.morphBackground, panel?.morphContent)
    }

    // Before ordering in (window alpha 0): incoming in its start state.
    func prepare() {
        incomingLevel = incoming.level
        outgoingLevel = outgoing.level
        let top = NSWindow.Level(rawValue: max(incomingLevel.rawValue, outgoingLevel.rawValue))
        incoming.level = top
        outgoing.level = top
        startBlurTrack()
        startShadowTrack()
        outgoing.ignoresMouseEvents = true
        let views = Self.parts(incoming)
        views.content?.alphaValue = 0
        if incomingIsLarge {
            Self.apply(incoming, largeAtSmall, duration: nil)
            views.background?.setWallpaperSlice(onScreen: smallFrame, duration: nil)
            // Translucent pair: the large background comes in as the small one leaves (see run()).
            if crossFadesBackgrounds { views.background?.alphaValue = 0 }
        } else {
            views.background?.alphaValue = 0
        }
        spreadSmallWindow()
        if !incomingIsLarge, let background = Self.parts(small).background {
            if let layer = background.layer {
                Self.setBackgroundPose(layer, atLarge: true, morph: self, duration: nil, timing: nil)
            }
            background.setWallpaperSlice(onScreen: largeFrame, duration: nil)   // wallpaper under that frame
        }
        if !incomingIsLarge, let content = Self.parts(small).content?.layer {
            Self.setTransform(content, scale: smallContentAtLarge, key: Self.contentKey, duration: nil, timing: nil)
        }
    }

    // Small panel's window → large frame, background + content kept where they were (centered),
    // rounded corners moved from the container to the background.
    private func spreadSmallWindow() {
        guard let container = small.contentView else { return }
        let views = Self.parts(small)
        container.autoresizesSubviews = false
        small.setFrame(largeFrame, display: false)
        // Where the small frame sits inside the large one (container coordinates).
        let origin = NSPoint(
            x: (smallFrame.minX - largeFrame.minX).rounded(),
            y: (container.isFlipped ? largeFrame.maxY - smallFrame.maxY : smallFrame.minY - largeFrame.minY).rounded())
        for view in [views.background as NSView?, views.content] { view?.setFrameOrigin(origin) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.layer?.cornerRadius = 0
        container.layer?.masksToBounds = false
        views.background?.layer?.cornerRadius = smallRadius
        views.background?.layer?.masksToBounds = true
        CATransaction.commit()
        smallWindowSpread = true
    }

    // Back to its own frame; on screen nothing moves.
    private func gatherSmallWindow() {
        guard smallWindowSpread, let container = small.contentView else { return }
        smallWindowSpread = false
        let views = Self.parts(small)
        small.setFrame(smallFrame, display: false)
        for view in [views.background as NSView?, views.content] { view?.setFrameOrigin(.zero) }
        container.autoresizesSubviews = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.layer?.cornerRadius = smallRadius
        container.layer?.masksToBounds = true
        views.background?.layer?.cornerRadius = 0
        views.background?.layer?.masksToBounds = false
        CATransaction.commit()
        if small.isVisible { small.displayIfNeeded() }
    }

    func run(completion: @escaping () -> Void) {
        let d = Self.duration
        let largeParts = Self.parts(large)
        let smallParts = Self.parts(small)
        if incomingIsLarge {
            // Expand: panel stays on top while its content and background leave.
            let swap = d * Self.expandSwap
            let curve = Self.expandCurve
            outgoing.order(.above, relativeTo: incoming.windowNumber)
            incoming.alphaValue = 1
            Self.apply(incoming, largeAtRest, duration: d, timing: curve)
            largeParts.background?.setWallpaperSlice(onScreen: nil, duration: d, timing: curve)
            if let content = smallParts.content?.layer {
                Self.setTransform(content, scale: smallContentAtLarge, key: Self.contentKey, duration: d, timing: curve)
            }
            if let background = smallParts.background {
                if let layer = background.layer {
                    Self.setBackgroundPose(layer, atLarge: true, morph: self, duration: d, timing: curve)
                }
                background.setWallpaperSlice(onScreen: largeFrame, duration: d, timing: curve)
            }
            Self.fade(smallParts.content, to: 0, delay: 0, length: swap, timing: .easeIn)
            if crossFadesBackgrounds {
                Self.fade(smallParts.background, to: 0, delay: 0, length: d / 4, timing: .linear)
                Self.compensatedFade(largeParts.background, topFrom: 1, topTo: 0, alpha: overlayAlpha,
                                     delay: 0, length: d / 4)
            } else {
                Self.fade(smallParts.background, to: 0, delay: 0, length: d / 4, timing: .easeIn)
            }
            Self.fade(largeParts.content, to: 1, delay: swap, length: d - swap, timing: .easeOut)
        } else {
            // Shrink: panel (on top, still invisible) fills in as Launchpad arrives.
            let swap = d * Self.shrinkSwap
            let curve = Self.shrinkCurve
            incoming.alphaValue = 1
            Self.apply(outgoing, largeAtSmall, duration: d, timing: curve)
            largeParts.background?.setWallpaperSlice(onScreen: smallFrame, duration: d, timing: curve)
            if let content = smallParts.content?.layer {
                Self.setTransform(content, scale: Self.identity, key: Self.contentKey, duration: d, timing: curve)
            }
            if let background = smallParts.background {
                if let layer = background.layer {
                    Self.setBackgroundPose(layer, atLarge: false, morph: self, duration: d, timing: curve)
                }
                background.setWallpaperSlice(onScreen: nil, duration: d, timing: curve)
            }
            Self.fade(largeParts.content, to: 0, delay: 0, length: swap, timing: .easeIn)
            Self.fade(smallParts.content, to: 1, delay: swap, length: d - swap, timing: .easeOut)
            if crossFadesBackgrounds {
                Self.fade(smallParts.background, to: 1, delay: d * 3 / 4, length: d / 4, timing: .linear)
                Self.compensatedFade(largeParts.background, topFrom: 0, topTo: 1, alpha: overlayAlpha,
                                     delay: d * 3 / 4, length: d / 4)
            } else {
                Self.fade(smallParts.background, to: 1, delay: d * 3 / 4, length: d / 4, timing: .easeOut)
            }
        }
        let motion = incomingIsLarge ? Self.expandCurve : Self.shrinkCurve
        blurTrack?.animate(duration: d, curve: motion)
        PanelShadow.shared.animateMorph(duration: d, curve: motion)
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { completion() }
    }

    // Shadow from the outgoing panel's frame / state to the incoming one's.
    private func startShadowTrack() {
        let outPanel = outgoing as? LaunchpadPanel
        let inPanel = incoming as? LaunchpadPanel
        PanelShadow.shared.beginMorph(
            below: outgoing, span: largeFrame,
            from: .init(frame: incomingIsLarge ? smallFrame : largeFrame, corner: outgoingRadius,
                        opacity: outPanel?.dropsShadow == true ? 1 : 0),
            to: .init(frame: incomingIsLarge ? largeFrame : smallFrame, corner: incomingRadius,
                      opacity: inPanel?.dropsShadow == true ? 1 : 0))
    }

    // Window-server blur during the morph: PanelBackdrop's window (already below the outgoing panel)
    // follows the large panel's visible frame / corner radius at one constant radius, then simply
    // stays as the incoming panel's blur. Nothing is switched off or on, so no flash or jump.
    private var blurTrack: MorphBlurTrack?

    private func startBlurTrack() {
        let frames = incomingIsLarge ? (smallFrame, largeFrame) : (largeFrame, smallFrame)
        let corners = incomingIsLarge ? (smallRadius, largeRadius) : (largeRadius, smallRadius)
        guard PanelBackdrop.shared.beginMorph(from: outgoing as? LaunchpadPanel, to: incoming as? LaunchpadPanel,
                                              frame: frames.0, corner: corners.0)
        else { return }
        blurTrack = MorphBlurTrack(frames: frames, corners: corners)
    }

    // Blur hands over to the incoming panel (frame / radius of its own, normally unchanged).
    private func endBlurTrack() {
        blurTrack?.cancel()
        blurTrack = nil
        PanelBackdrop.shared.endMorph(owner: incoming as? LaunchpadPanel)
    }

    // Incoming at its final look (also when cut short).
    func settleIncoming() {
        if !incomingIsLarge { gatherSmallWindow() }
        Self.restore(incoming, radius: incomingRadius)
        // A panel already closing on its own (lost key) keeps its fade-out.
        if !incoming.isVisible || incoming.isKeyWindow { Self.setAlpha(incoming, 1) }
        endBlurTrack()
        PanelShadow.shared.endMorph(owner: incoming as? LaunchpadPanel)
    }

    // Outgoing after its hide(): back to normal for its next show.
    func resetOutgoing() {
        // Own levels back once the outgoing panel is gone (earlier, it could cover the incoming one).
        outgoing.level = outgoingLevel
        incoming.level = incomingLevel
        if let panel = incoming as? LaunchpadPanel {
            PanelBackdrop.shared.update(for: panel)
            PanelShadow.shared.update(for: panel)
        }
        if incomingIsLarge { gatherSmallWindow() }
        Self.restore(outgoing, radius: outgoingRadius)
        Self.setAlpha(outgoing, 1)
        outgoing.ignoresMouseEvents = false
    }

    // Scale 1, own radius and wallpaper slice, both layers opaque; running animations dropped.
    private static func restore(_ window: NSWindow, radius: CGFloat) {
        apply(window, Pose(scale: identity, radius: radius), duration: nil)
        let views = Self.parts(window)
        views.background?.setWallpaperSlice(onScreen: nil, duration: nil)
        if let background = views.background?.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            background.removeAnimation(forKey: backgroundKey)
            background.removeAnimation(forKey: backgroundRadiusKey)
            background.transform = CATransform3DIdentity
            CATransaction.commit()
        }
        for view in [views.background as NSView?, views.content] {
            view?.layer?.removeAnimation(forKey: fadeKey)
            view?.alphaValue = 1
        }
    }

    // Zero-duration animator: also stops a running alpha animation.
    private static func setAlpha(_ window: NSWindow, _ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.animator().alphaValue = alpha
        }
    }

    // Small panel's background on the large panel's visible frame (atLarge) or on its own (identity):
    // it moves with the shrinking / growing frame, so it never shows its final rect early.
    // Scale + move around its center; corner radius so the on-screen radius matches the large one.
    private static func setBackgroundPose(_ layer: CALayer, atLarge: Bool, morph: PanelMorph,
                                          duration: TimeInterval?, timing: CAMediaTimingFunction?) {
        let r = morph.ratio
        let scale = atLarge ? CGSize(width: 1 / max(r.width, 0.01), height: 1 / max(r.height, 0.01)) : identity
        let offset = atLarge ? CGSize(width: morph.largeFrame.midX - morph.smallFrame.midX,
                                      height: morph.largeFrame.midY - morph.smallFrame.midY) : .zero
        let mean = (scale.width * scale.height).squareRoot()
        let radius = atLarge ? morph.largeRadius / max(mean, 0.01) : morph.smallRadius

        let size = layer.bounds.size
        let dx = (0.5 - layer.anchorPoint.x) * size.width
        let dy = (0.5 - layer.anchorPoint.y) * size.height
        var target = CATransform3DMakeTranslation(dx, dy, 0)
        target = CATransform3DScale(target, scale.width, scale.height, 1)
        target = CATransform3DTranslate(target, -dx, -dy, 0)
        if offset != .zero {
            // Unscaled points in the container (y up unless its layer is flipped).
            let ySign: CGFloat = layer.superlayer?.isGeometryFlipped == true ? -1 : 1
            target = CATransform3DConcat(target, CATransform3DMakeTranslation(offset.width, ySign * offset.height, 0))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let duration {
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            move.toValue = NSValue(caTransform3D: target)
            let corner = CABasicAnimation(keyPath: "cornerRadius")
            corner.fromValue = layer.presentation()?.cornerRadius ?? layer.cornerRadius
            corner.toValue = radius
            for animation in [move, corner] {
                animation.duration = duration
                animation.timingFunction = timing ?? CAMediaTimingFunction(name: .easeOut)
            }
            layer.add(move, forKey: backgroundKey)
            layer.add(corner, forKey: backgroundRadiusKey)
        } else {
            layer.removeAnimation(forKey: backgroundKey)
            layer.removeAnimation(forKey: backgroundRadiusKey)
        }
        layer.transform = target
        layer.cornerRadius = radius
        CATransaction.commit()
    }

    // Both backgrounds are translucent colors over the windows behind: stacked they would look
    // brighter, so they cross-fade (opaque ones just overlap, which is invisible).
    private var crossFadesBackgrounds: Bool {
        Self.parts(large).background?.showsWindowsBehind == true
            && Self.parts(small).background?.showsWindowsBehind == true
    }

    // Alpha of the small (top) panel's color layer, for the compensated cross-fade.
    private var overlayAlpha: CGFloat {
        Self.parts(small).background?.overlayAlpha ?? 0.5
    }

    // Large (bottom) background against the small one fading linearly topFrom → topTo:
    // a·x + a·y − a²·x·y = a  →  x = (1 − y) / (1 − a·y), so the combined layer stays as dense as one.
    private static func compensatedFade(_ view: NSView?, topFrom: CGFloat, topTo: CGFloat, alpha a: CGFloat,
                                        delay: TimeInterval, length: TimeInterval) {
        guard let view, let layer = view.layer else { return }
        let steps = 12
        let values: [Float] = (0...steps).map { i in
            let y = topFrom + (topTo - topFrom) * CGFloat(i) / CGFloat(steps)
            return Float(min(max((1 - y) / max(1 - a * y, 0.001), 0), 1))
        }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values
        animation.calculationMode = .linear
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        animation.duration = length
        animation.fillMode = .backwards
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.add(animation, forKey: fadeKey)
        view.alphaValue = CGFloat(values.last ?? 1)
        CATransaction.commit()
    }

    // View opacity after a delay; the start value holds until then (fillMode backwards).
    private static func fade(_ view: NSView?, to value: CGFloat, delay: TimeInterval, length: TimeInterval,
                             timing: CAMediaTimingFunctionName) {
        guard let view, let layer = view.layer else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = Float(value)
        animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        animation.duration = length
        animation.fillMode = .backwards
        animation.timingFunction = CAMediaTimingFunction(name: timing)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.add(animation, forKey: fadeKey)
        view.alphaValue = value
        CATransaction.commit()
    }

    // Scales the window's content layer around its center (anchor-independent, flip-safe)
    // and sets its corner radius, animated together.
    private static func apply(_ window: NSWindow, _ pose: Pose, duration: TimeInterval?,
                              timing: CAMediaTimingFunction? = nil) {
        guard let layer = window.contentView?.layer else { return }
        let size = layer.bounds.size
        let dx = (0.5 - layer.anchorPoint.x) * size.width
        let dy = (0.5 - layer.anchorPoint.y) * size.height
        var target = CATransform3DMakeTranslation(dx, dy, 0)
        target = CATransform3DScale(target, pose.scale.width, pose.scale.height, 1)
        target = CATransform3DTranslate(target, -dx, -dy, 0)
        if pose.offset != .zero {
            // Unscaled points in the superlayer (the window's root layer, y up unless flipped).
            let ySign: CGFloat = layer.superlayer?.isGeometryFlipped == true ? -1 : 1
            target = CATransform3DConcat(target, CATransform3DMakeTranslation(pose.offset.width, ySign * pose.offset.height, 0))
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let duration {
            let curve = timing ?? CAMediaTimingFunction(name: .easeOut)
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            move.toValue = NSValue(caTransform3D: target)
            let corner = CABasicAnimation(keyPath: "cornerRadius")
            corner.fromValue = layer.presentation()?.cornerRadius ?? layer.cornerRadius
            corner.toValue = pose.radius
            for animation in [move, corner] {
                animation.duration = duration
                animation.timingFunction = curve
            }
            layer.add(move, forKey: transformKey)
            layer.add(corner, forKey: radiusKey)
        } else {
            layer.removeAnimation(forKey: transformKey)
            layer.removeAnimation(forKey: radiusKey)
        }
        layer.transform = target
        layer.cornerRadius = pose.radius
        CATransaction.commit()
        if let content = Self.parts(window).content?.layer {
            setTransform(content, scale: pose.contentScale, key: contentKey, duration: duration, timing: timing)
        }
    }

    // Center scale on a plain layer (content compensation; identity = Launchpad's normal icon scale).
    private static func setTransform(_ layer: CALayer, scale: CGSize, key: String, duration: TimeInterval?,
                                     timing: CAMediaTimingFunction?) {
        let size = layer.bounds.size
        let dx = (0.5 - layer.anchorPoint.x) * size.width
        let dy = (0.5 - layer.anchorPoint.y) * size.height
        var target = CATransform3DMakeTranslation(dx, dy, 0)
        target = CATransform3DScale(target, scale.width, scale.height, 1)
        target = CATransform3DTranslate(target, -dx, -dy, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let duration {
            let move = CABasicAnimation(keyPath: "transform")
            move.fromValue = NSValue(caTransform3D: layer.presentation()?.transform ?? layer.transform)
            move.toValue = NSValue(caTransform3D: target)
            move.duration = duration
            move.timingFunction = timing ?? CAMediaTimingFunction(name: .easeOut)
            layer.add(move, forKey: key)
        } else {
            layer.removeAnimation(forKey: key)
        }
        layer.transform = target
        CATransaction.commit()
    }
}

// MARK: - Panel header
// Clipboard / Workflow panel, left of the search field: title on the first line, shortcut hints
// on one second line; the two lines as a block are vertically centered on the search field.
final class PanelHeaderView: FlippedView {
    struct Hint {
        let keys: String
        let action: String
    }

    private static let titleHeight: CGFloat = 18
    private static let hintHeight: CGFloat = 15
    private static let lineGap: CGFloat = 2
    private static let textPadding: CGFloat = 8
    private static let hintFont = NSFont.systemFont(ofSize: 11)
    private static let keyFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    private let titleLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    init(title: String, hints: [Hint]) {
        super.init(frame: .zero)
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        hintLabel.attributedStringValue = Self.hintText(hints)
        hintLabel.lineBreakMode = .byClipping
        titleLabel.lineBreakMode = .byClipping
        addSubview(titleLabel)
        addSubview(hintLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Measured from the text itself (+ the label's inner padding): the field's intrinsic width
    // came out a few points short for the mixed-weight hint line and clipped its last character.
    var preferredSize: NSSize {
        let hintWidth = hintLabel.attributedStringValue.size().width
        let titleWidth = (titleLabel.stringValue as NSString).size(withAttributes: [.font: titleLabel.font ?? NSFont.systemFont(ofSize: 14, weight: .semibold)]).width
        let width = ceil(max(hintWidth, titleWidth)) + Self.textPadding
        return NSSize(width: width, height: Self.titleHeight + Self.lineGap + Self.hintHeight)
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.titleHeight)
        hintLabel.frame = NSRect(x: 0, y: Self.titleHeight + Self.lineGap, width: bounds.width, height: Self.hintHeight)
    }

    // "⌘K/J Up/Down   ⌘⇧K/J Switch": keys a shade brighter than their action.
    private static func hintText(_ hints: [Hint]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (index, hint) in hints.enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: "   ", attributes: [.font: hintFont]))
            }
            text.append(NSAttributedString(string: hint.keys, attributes: [
                .font: keyFont, .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            text.append(NSAttributedString(string: " " + hint.action, attributes: [
                .font: hintFont, .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
        }
        return text
    }
}

// MARK: - Target display
// Shared by Launchpad, Clipboard and Workflow panel.
@MainActor
enum PanelScreen {
    // Display under the mouse, or the main display (menu bar) when the setting is off.
    static func target() -> NSScreen? {
        if Preferences.shared.panelsFollowMouseScreen {
            let mouse = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
                return screen
            }
        }
        // screens[0] holds the menu bar; NSScreen.main is just the key window's screen.
        return NSScreen.screens.first ?? NSScreen.main
    }
}

// MARK: - Space switch
// Current Space of one display (private CGS call, resolved like WindowBlur; nil = unavailable).
enum DisplaySpace {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias CurrentSpaceFn = @convention(c) (Int32, CFString) -> UInt64

    private static let connection: ConnectionFn? = symbol("CGSDefaultConnectionForThread")
    private static let currentSpace: CurrentSpaceFn? = symbol("CGSManagedDisplayGetCurrentSpace")

    private static func symbol<T>(_ name: String) -> T? {
        guard let pointer = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    static func current(on screen: NSScreen) -> UInt64? {
        guard let connection, let currentSpace,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid)
        else { return nil }
        let cid = connection()
        var space = currentSpace(cid, string)
        // "Displays have separate Spaces" off: all displays share the "Main" managed display.
        if space == 0 { space = currentSpace(cid, "Main" as CFString) }
        return space == 0 ? nil : space
    }
}

// Closes a panel when the Space under it changes (4-finger swipe, ⌃←/→, entering a full-screen app),
// like the macOS 15 Launchpad. The panel already slid away with its Space; order it out so it does
// not wait there. Focus moving to another display's Space (separate Spaces) does not count.
@MainActor
final class PanelSpaceGuard {
    private weak var panel: NSWindow?
    private let onLeave: () -> Void
    private var space: UInt64?
    private var armed = false   // false until the first real show (skips the launch warm-up)
    private var shownAt: TimeInterval = 0
    // Without the private call: ignore the change caused by the show itself (other display).
    private static let fallbackGrace: TimeInterval = 0.5

    // Lives as long as its controller (app lifetime); the observer only holds it weakly.
    init(panel: NSWindow, onLeave: @escaping () -> Void) {
        self.panel = panel
        self.onLeave = onLeave
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceDidChange() }
        }
    }

    // Right after the panel is ordered in.
    func panelDidShow() {
        armed = true
        shownAt = ProcessInfo.processInfo.systemUptime
        space = panel?.screen.flatMap(DisplaySpace.current(on:))
    }

    private func spaceDidChange() {
        guard armed, let panel, panel.isVisible else { return }
        if let old = space, let screen = panel.screen, let now = DisplaySpace.current(on: screen) {
            guard now != old else { return }   // another display's Space changed
        } else if ProcessInfo.processInfo.systemUptime - shownAt < Self.fallbackGrace {
            return
        }
        onLeave()
    }
}

// MARK: - Panel backdrop (window-server blur)
// One clear, click-through window right below the visible panel carries the blur of what is behind
// it (the panels never blur themselves). Frame / corners / radius follow the owner panel; during a
// morph PanelMorph drives the frame instead, and the owner changes at the end without any toggle.
@MainActor
final class PanelBackdrop {
    static let shared = PanelBackdrop()

    private let window = BlurHelperWindow(contentRect: .zero, styleMask: .borderless,
                                          backing: .buffered, defer: false)
    private weak var owner: LaunchpadPanel?
    private var isMorphing = false
    private var appliedRadius = -1

    // Panel shown / moved / resized / faded / re-configured.
    func update(for panel: LaunchpadPanel) {
        guard !isMorphing, WindowBlur.isAvailable else { return }
        guard panel.isVisible, panel.behindBlurRadius > 0 else {
            if owner === panel { hide() }
            return
        }
        owner = panel
        place(panel.frame, corner: panel.cornerMaskRadius)
        keepBelow(panel)
        setRadius(Int((CGFloat(panel.behindBlurRadius) * panel.alphaValue).rounded()))
    }

    func panelDidHide(_ panel: LaunchpadPanel) {
        guard owner === panel, !isMorphing else { return }
        hide()
    }

    // Morph start: below the outgoing panel at the start frame, constant radius
    // (the outgoing panel's, or the incoming one's when the outgoing has none). false = no blur.
    func beginMorph(from outgoing: LaunchpadPanel?, to incoming: LaunchpadPanel?, frame: NSRect, corner: CGFloat) -> Bool {
        guard WindowBlur.isAvailable, let outgoing else { return false }
        let outRadius = outgoing.behindBlurRadius
        let radius = outRadius > 0 ? outRadius : (incoming?.behindBlurRadius ?? 0)
        guard radius > 0 else { return false }
        isMorphing = true
        place(frame, corner: corner)
        keepBelow(outgoing)
        setRadius(radius)
        return true
    }

    func setMorphFrame(_ frame: NSRect, corner: CGFloat) {
        guard isMorphing else { return }
        place(frame, corner: corner)
    }

    // Morph end (or cut short): the incoming panel owns the blur; no reorder, so no flicker.
    func endMorph(owner panel: LaunchpadPanel?) {
        guard isMorphing else { return }
        isMorphing = false
        owner = panel
        if let panel { update(for: panel) } else { hide() }
    }

    // Same level as the panel, right below it. Ordered only when coming in or when the level
    // changed (a level change moves a window to the front of its new level).
    private func keepBelow(_ panel: NSWindow) {
        guard !window.isVisible || window.level != panel.level else { return }
        window.level = panel.level
        window.order(.below, relativeTo: panel.windowNumber)
        appliedRadius = -1
    }

    private func place(_ frame: NSRect, corner: CGFloat) {
        window.setFrame(frame.integral, display: false)
        window.cornerMaskRadius = corner.rounded()
    }

    private func setRadius(_ radius: Int) {
        guard radius != appliedRadius else { return }
        if WindowBlur.set(window, radius: radius) { appliedRadius = radius }
    }

    private func hide() {
        owner = nil
        setRadius(0)
        window.orderOut(nil)
        appliedRadius = -1
    }
}

// MARK: - Panel shadow
// One clear, click-through window below the visible panel draws its drop shadow, cut out under the
// panel shape. A window-server shadow is drawn under the whole window, so it showed through a
// translucent background and made a panel darker than the same background without a shadow.
// The window is larger than the panel by `margin` so the blur of the shadow is not clipped.
// During a morph it spans the large frame and the shape is animated with the morph's curve.
@MainActor
final class PanelShadow {
    static let shared = PanelShadow()

    struct State {
        let frame: NSRect      // panel frame (screen)
        let corner: CGFloat
        let opacity: Float     // 0 = no shadow, 1 = full
    }

    // Tuning: roughly the look of a macOS panel shadow.
    private static let opacity: Float = 0.32
    private static let radius: CGFloat = 16
    private static let drop: CGFloat = 10
    private static let margin: CGFloat = 64
    private static let pathKey = "panelShadowPath"
    private static let fadeKey = "panelShadowFade"

    private let window = BlurHelperWindow(contentRect: .zero, styleMask: .borderless,
                                          backing: .buffered, defer: false)
    private let host = NSView()
    private let shadowLayer = CALayer()
    private let mask = CAShapeLayer()
    private weak var owner: LaunchpadPanel?
    private var isMorphing = false
    private var morphTarget: State?

    private init() {
        let root = CALayer()
        host.layer = root
        host.wantsLayer = true   // layer-hosting, y up
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = Self.opacity
        shadowLayer.shadowRadius = Self.radius
        shadowLayer.shadowOffset = CGSize(width: 0, height: -Self.drop)
        mask.fillRule = .evenOdd
        shadowLayer.mask = mask
        root.addSublayer(shadowLayer)
        window.contentView = host
    }

    // Panel shown / moved / resized / faded / re-configured.
    func update(for panel: LaunchpadPanel) {
        guard !isMorphing else { return }
        // Panel being replaced (⌘⇧J/K): the incoming one already owns the shadow.
        if let owner, owner !== panel, owner.isVisible, PanelSwitch.isOutgoing(panel) { return }
        guard panel.isVisible, panel.dropsShadow else {
            if owner === panel { hide() }
            return
        }
        owner = panel
        let state = State(frame: panel.frame, corner: panel.cornerMaskRadius, opacity: 1)
        place(span: state.frame)
        apply(state, duration: nil, curve: nil)
        window.alphaValue = panel.alphaValue
        keepBelow(panel)
    }

    func panelDidHide(_ panel: LaunchpadPanel) {
        guard owner === panel, !isMorphing else { return }
        hide()
    }

    // Morph start: below the outgoing (visible) panel, spanning the large frame, at the outgoing shadow.
    // The incoming panel is ordered in above it, so the shadow stays under both.
    func beginMorph(below panel: NSWindow, span: NSRect, from: State, to: State) {
        guard from.opacity > 0 || to.opacity > 0 else {
            hide()
            return
        }
        isMorphing = true
        morphTarget = to
        place(span: span)
        apply(from, duration: nil, curve: nil)
        window.alphaValue = 1
        keepBelow(panel)
    }

    // Same duration / curve as the panel layers. Fade in: visible early; fade out: gone by half time.
    func animateMorph(duration: TimeInterval, curve: CAMediaTimingFunction) {
        guard isMorphing, let target = morphTarget else { return }
        apply(target, duration: duration, curve: curve)
    }

    // Morph end (or cut short): back to following the incoming panel.
    func endMorph(owner panel: LaunchpadPanel?) {
        guard isMorphing else { return }
        isMorphing = false
        morphTarget = nil
        shadowLayer.removeAllAnimations()
        mask.removeAllAnimations()
        owner = panel
        if let panel { update(for: panel) } else { hide() }
    }

    // MARK: Private

    private func place(span frame: NSRect) {
        window.setFrame(frame.insetBy(dx: -Self.margin, dy: -Self.margin).integral, display: false)
        let bounds = CGRect(origin: .zero, size: window.frame.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadowLayer.frame = bounds
        mask.frame = bounds
        CATransaction.commit()
    }

    // Panel rect in the shadow window (y up).
    private func local(_ rect: NSRect) -> CGRect {
        CGRect(x: rect.minX - window.frame.minX, y: rect.minY - window.frame.minY,
               width: rect.width, height: rect.height)
    }

    private func apply(_ state: State, duration: TimeInterval?, curve: CAMediaTimingFunction?) {
        let rect = local(state.frame)
        let path = Self.roundedPath(rect, radius: state.corner)
        let cutout = CGMutablePath()
        cutout.addRect(shadowLayer.bounds.insetBy(dx: -1, dy: -1))
        cutout.addPath(path)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let duration, let curve {
            let shape = CABasicAnimation(keyPath: "shadowPath")
            shape.fromValue = shadowLayer.presentation()?.shadowPath ?? shadowLayer.shadowPath
            shape.toValue = path
            let cut = CABasicAnimation(keyPath: "path")
            cut.fromValue = mask.presentation()?.path ?? mask.path
            cut.toValue = cutout
            for animation in [shape, cut] {
                animation.duration = duration
                animation.timingFunction = curve
            }
            shadowLayer.add(shape, forKey: Self.pathKey)
            mask.add(cut, forKey: Self.pathKey)
            let from = shadowLayer.presentation()?.opacity ?? shadowLayer.opacity
            if from != state.opacity {
                let fadeIn = state.opacity > from
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = from
                fade.toValue = state.opacity
                fade.duration = fadeIn ? duration : duration / 2
                fade.timingFunction = CAMediaTimingFunction(name: fadeIn ? .easeOut : .easeIn)
                shadowLayer.add(fade, forKey: Self.fadeKey)
            }
        } else {
            shadowLayer.removeAllAnimations()
            mask.removeAllAnimations()
        }
        shadowLayer.shadowPath = path
        mask.path = cutout
        shadowLayer.opacity = state.opacity
        CATransaction.commit()
    }

    private static func roundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        // Radius > 0 keeps the element count fixed, so the paths interpolate.
        let r = min(max(radius, 0.5), min(rect.width, rect.height) / 2)
        return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    // Same level as the panel, right below it (re-ordered only when needed, like PanelBackdrop).
    private func keepBelow(_ panel: NSWindow) {
        guard !window.isVisible || window.level != panel.level else { return }
        window.level = panel.level
        window.order(.below, relativeTo: panel.windowNumber)
    }

    private func hide() {
        owner = nil
        window.orderOut(nil)
    }
}

// MARK: - Morph blur track
// Moves PanelBackdrop's window per display frame, in step with PanelMorph's layer animation
// (same duration and timing curve).
@MainActor
final class MorphBlurTrack: NSObject {
    private let frames: (NSRect, NSRect)
    private let corners: (CGFloat, CGFloat)
    private var duration: TimeInterval = 0.5
    private var ease: (Double) -> Double = { $0 }
    private var startTime: CFTimeInterval = 0
    private var link: CADisplayLink?

    init(frames: (NSRect, NSRect), corners: (CGFloat, CGFloat)) {
        self.frames = frames
        self.corners = corners
        super.init()
    }

    func animate(duration: TimeInterval, curve: CAMediaTimingFunction) {
        self.duration = max(duration, 0.01)
        ease = Self.easing(curve)
        startTime = CACurrentMediaTime()
        link?.invalidate()
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(frames.0) }) ?? NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func cancel() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = min(1, (CACurrentMediaTime() - startTime) / duration)
        let p = ease(t)
        let a = frames.0, b = frames.1
        let frame = NSRect(x: lerp(a.minX, b.minX, p), y: lerp(a.minY, b.minY, p),
                           width: lerp(a.width, b.width, p), height: lerp(a.height, b.height, p))
        PanelBackdrop.shared.setMorphFrame(frame, corner: lerp(corners.0, corners.1, p))
        if t >= 1 {   // hold the end state until the morph settles
            cancel()
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ p: Double) -> CGFloat {
        a + (b - a) * CGFloat(p)
    }

    // Cubic bezier of a CAMediaTimingFunction: x (time) → y (progress).
    private static func easing(_ curve: CAMediaTimingFunction) -> (Double) -> Double {
        var c1: [Float] = [0, 0]
        var c2: [Float] = [0, 0]
        curve.getControlPoint(at: 1, values: &c1)
        curve.getControlPoint(at: 2, values: &c2)
        let x1 = Double(c1[0]), y1 = Double(c1[1]), x2 = Double(c2[0]), y2 = Double(c2[1])
        let bez: (Double, Double, Double) -> Double = { s, p1, p2 in
            let u = 1 - s
            return 3 * u * u * s * p1 + 3 * u * s * s * p2 + s * s * s
        }
        return { x in
            guard x > 0 else { return 0 }
            guard x < 1 else { return 1 }
            // Bisection on the monotonic x(s).
            var lo = 0.0, hi = 1.0, s = x
            for _ in 0..<24 {
                s = (lo + hi) / 2
                if bez(s, x1, x2) < x { lo = s } else { hi = s }
            }
            return bez(s, y1, y2)
        }
    }
}

// Clear, click-through window that only carries the window-server blur.
final class BlurHelperWindow: NSWindow {
    // Rounded window shape for the window server, so the blur has the panel's corners.
    var cornerMaskRadius: CGFloat = 0 {
        didSet {
            guard cornerMaskRadius != oldValue else { return }
            let changed = NSSelectorFromString("_cornerMaskChanged")
            if responds(to: changed) { _ = perform(changed) }
        }
    }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask,
                  backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Same Space handling as the panels, so the blur slides away together with its panel.
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Private NSWindow hook (no `override`: not visible to Swift). nil = plain rectangle.
    @objc func _cornerMask() -> NSImage? {
        Self.cornerMaskImage(radius: cornerMaskRadius)
    }

    // Stretchable rounded-rect mask; nil for radius 0.
    static func cornerMaskImage(radius r: CGFloat) -> NSImage? {
        guard r > 0 else { return nil }
        let size = NSSize(width: r * 2 + 1, height: r * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}
