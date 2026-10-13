import AppKit

// Borderless, non-activating floating panel (Spotlight style):
// it takes keyboard focus without activating AppPad, so the hotkey works from any app
// and closing it leaves the previous app frontmost.
final class LaunchpadPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?
    // Sees every keyDown before the field editor (Workflow panel: ⌥ / ⌃ in-panel shortcuts).
    var keyDownHandler: ((NSEvent) -> Bool)?
    // Set by the owning controller: the two layers PanelMorph fades / re-slices separately.
    weak var morphBackground: LaunchpadBackgroundView?
    weak var morphContent: NSView?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style.union(.nonactivatingPanel), backing: backingStoreType, defer: flag)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Replayed trackpad taps
    // A tap that stops a running swipe is eaten by macOS (no click). The controller replays it
    // here; whichever of the replay / a real click comes second is dropped, so it acts once.

    private static let replayWindow: TimeInterval = 0.35
    private var lastRealMouseDown: TimeInterval = -1
    private var lastReplay: TimeInterval = -1
    private var dropNextMouseUp = false
    private var isReplaying = false

    override func sendEvent(_ event: NSEvent) {
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
// Different size (Launchpad ⇄ Clipboard / Workflows): PanelMorph expands / shrinks between the two
// frames, contents swap at the halfway point, then the old one leaves.
// (Hiding first and fading in from alpha 0 briefly showed the desktop → flash.)
@MainActor
enum PanelSwitch {
    private static var outgoing: NSWindow?
    private static var hideOutgoing: (() -> Void)?
    private static var morph: PanelMorph?
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
            return false
        }
        return true
    }

    // Incoming panel during a hand-over, after its frame is set and before ordering in:
    // the alpha to order in with (0 = morph starts transparent, 1 = instant hand-over).
    static func incomingAlpha(for window: NSWindow) -> CGFloat {
        morph = nil
        guard let outgoing, outgoing !== window, let plan = PanelMorph(from: outgoing, to: window) else { return 1 }
        morph = plan
        plan.prepare()
        return 0
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
    }
}

// MARK: - Panel morph
// Launchpad ⇄ Clipboard / Workflows (different size, same center). Only the larger panel moves:
// its frame (content layer scale + corner radius) goes between its own frame and the smaller one's,
// its wallpaper slice follows so the blur always matches what is under it.
// The frame lands exactly on the other frame; the content inside scales uniformly (no squashed icons).
// Content never overlaps: one panel's content fades out, then the other's fades in.
// The smaller panel sits above the larger one the whole time, its background only shows while the
// frames (nearly) coincide: last quarter when shrinking, first quarter when expanding.
//   shrink (Launchpad → panel): icons out [0, ⅔], panel content in [⅔, 1], panel background in [¾, 1]
//   expand (panel → Launchpad): panel content out [0, ⅓], panel background out [0, ¼], icons in [⅓, 1]
@MainActor
final class PanelMorph {
    private static let duration: TimeInterval = 0.5
    // Content hand-over point (fraction of duration).
    private static let shrinkSwap: Double = 2.0 / 3
    private static let expandSwap: Double = 1.0 / 3
    private static let frameCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
    private static let transformKey = "panelMorph"
    private static let radiusKey = "panelMorphRadius"
    private static let fadeKey = "panelMorphFade"
    private static let contentKey = "panelMorphContent"

    let incoming: NSWindow
    let outgoing: NSWindow
    private let incomingIsLarge: Bool
    private let ratio: CGSize          // small frame / large frame
    private let incomingRadius: CGFloat
    private let outgoingRadius: CGFloat
    private var incomingHadShadow = false
    private var outgoingHadShadow = false

    private struct Pose {
        let scale: CGSize
        let radius: CGFloat            // layer cornerRadius (before scaling)
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
        guard outgoing.isVisible, a.width > 0, a.height > 0, b.width > 0, b.height > 0,
              abs(a.midX - b.midX) <= 4, abs(a.midY - b.midY) <= 4 else { return nil }
        let incomingIsLarge = b.width * b.height > a.width * a.height
        let largeFrame = incomingIsLarge ? b : a
        let smallFrame = incomingIsLarge ? a : b
        guard largeFrame.width - smallFrame.width > 24 || largeFrame.height - smallFrame.height > 24 else { return nil }
        self.incoming = incoming
        self.outgoing = outgoing
        self.incomingIsLarge = incomingIsLarge
        ratio = CGSize(width: min(1, smallFrame.width / largeFrame.width),
                       height: min(1, smallFrame.height / largeFrame.height))
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
                    contentScale: CGSize(width: uniform / max(ratio.width, 0.01),
                                         height: uniform / max(ratio.height, 0.01)))
    }
    private var largeAtRest: Pose { Pose(scale: Self.identity, radius: largeRadius) }
    private static let identity = CGSize(width: 1, height: 1)

    private static func parts(_ window: NSWindow) -> (background: LaunchpadBackgroundView?, content: NSView?) {
        let panel = window as? LaunchpadPanel
        return (panel?.morphBackground, panel?.morphContent)
    }

    // Before ordering in (window alpha 0): incoming in its start state.
    func prepare() {
        incomingHadShadow = incoming.hasShadow
        outgoingHadShadow = outgoing.hasShadow
        // A window shadow would not follow the scaling / fading layers.
        incoming.hasShadow = false
        outgoing.hasShadow = false
        outgoing.ignoresMouseEvents = true
        let views = Self.parts(incoming)
        views.content?.alphaValue = 0
        if incomingIsLarge {
            Self.apply(incoming, largeAtSmall, duration: nil)
            views.background?.setWallpaperSlice(onScreen: small.frame, duration: nil)
        } else {
            views.background?.alphaValue = 0
        }
    }

    func run(completion: @escaping () -> Void) {
        let d = Self.duration
        let largeParts = Self.parts(large)
        let smallParts = Self.parts(small)
        if incomingIsLarge {
            // Expand: panel stays on top while its content and background leave.
            let swap = d * Self.expandSwap
            outgoing.order(.above, relativeTo: incoming.windowNumber)
            incoming.alphaValue = 1
            Self.apply(incoming, largeAtRest, duration: d, timing: Self.frameCurve)
            largeParts.background?.setWallpaperSlice(onScreen: nil, duration: d, timing: Self.frameCurve)
            Self.fade(smallParts.content, to: 0, delay: 0, length: swap, timing: .easeIn)
            Self.fade(smallParts.background, to: 0, delay: 0, length: d / 4, timing: .easeIn)
            Self.fade(largeParts.content, to: 1, delay: swap, length: d - swap, timing: .easeOut)
        } else {
            // Shrink: panel (on top, still invisible) fills in as Launchpad arrives.
            let swap = d * Self.shrinkSwap
            incoming.alphaValue = 1
            Self.apply(outgoing, largeAtSmall, duration: d, timing: Self.frameCurve)
            largeParts.background?.setWallpaperSlice(onScreen: incoming.frame, duration: d, timing: Self.frameCurve)
            Self.fade(largeParts.content, to: 0, delay: 0, length: swap, timing: .easeIn)
            Self.fade(smallParts.content, to: 1, delay: swap, length: d - swap, timing: .easeOut)
            Self.fade(smallParts.background, to: 1, delay: d * 3 / 4, length: d / 4, timing: .easeOut)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d) { completion() }
    }

    // Incoming at its final look (also when cut short).
    func settleIncoming() {
        Self.restore(incoming, radius: incomingRadius)
        // A panel already closing on its own (lost key) keeps its fade-out.
        if !incoming.isVisible || incoming.isKeyWindow { Self.setAlpha(incoming, 1) }
        incoming.hasShadow = incomingHadShadow
        incoming.invalidateShadow()
    }

    // Outgoing after its hide(): back to normal for its next show.
    func resetOutgoing() {
        Self.restore(outgoing, radius: outgoingRadius)
        Self.setAlpha(outgoing, 1)
        outgoing.ignoresMouseEvents = false
        outgoing.hasShadow = outgoingHadShadow
    }

    // Scale 1, own radius and wallpaper slice, both layers opaque; running animations dropped.
    private static func restore(_ window: NSWindow, radius: CGFloat) {
        apply(window, Pose(scale: identity, radius: radius), duration: nil)
        let views = Self.parts(window)
        views.background?.setWallpaperSlice(onScreen: nil, duration: nil)
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
