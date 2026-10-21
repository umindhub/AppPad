import AppKit
import SwiftUI

// First-launch welcome guide: features, pinch, clipboard, Spotlight's ⌘Space, app shortcuts, AI, permissions.
// Replaces the separate one-time pinch and Spotlight guides; can be reopened from Settings › About.
enum OnboardingGuide {
    private static let shownKey = "onboardingShown"
    // Keys of the older one-time guides (PinchSetupGuide / SpotlightShortcut).
    private static let legacyKeys = ["pinchSetupGuideShown", "spotlightGuideShown"]

    // Called when the guide closes; true = finished with "Open AppPad".
    static var onClose: ((Bool) -> Void)?
    // Opens Settings on a tab (set by AppDelegate).
    static var openSettings: ((SettingsTab) -> Void)?

    private static var controller: OnboardingWindowController?

    static var isVisible: Bool { controller != nil }

    // New installs only: users who already saw the older guides are not asked again.
    static var needsShowing: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: shownKey) { return false }
        if legacyKeys.contains(where: { defaults.bool(forKey: $0) }) {
            defaults.set(true, forKey: shownKey)
            return false
        }
        return true
    }

    static func show() {
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: shownKey)
        // The guide covers both old one-time hints.
        legacyKeys.forEach { defaults.set(true, forKey: $0) }
        if let controller {
            controller.present()
            return
        }
        let controller = OnboardingWindowController { finished in
            OnboardingGuide.controller = nil
            OnboardingGuide.onClose?(finished)
        }
        self.controller = controller
        controller.present()
    }
}

extension Notification.Name {
    // userInfo["step"]: +1 next page, -1 previous page.
    static let onboardingSwipe = Notification.Name("AppPadOnboardingSwipe")
}

// Two-finger horizontal swipe (trackpad) or horizontal wheel (mouse) → one page per gesture.
private final class OnboardingSwipeTracker {
    private var monitor: Any?
    private var distance: CGFloat = 0
    private var vertical: CGFloat = 0
    private var fired = false
    private var lastWheelStep = Date.distantPast

    private static let threshold: CGFloat = 40
    private static let wheelCooldown: TimeInterval = 0.35

    init(window: NSWindow) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            self.handle(event)
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        // Finger direction, independent of the natural scrolling setting.
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX

        // Mouse wheel / no gesture phase: one step per notch, with a short cooldown.
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), dx != 0,
                  Date().timeIntervalSince(lastWheelStep) > Self.wheelCooldown else { return }
            lastWheelStep = Date()
            post(dx < 0 ? 1 : -1)
            return
        }
        // Momentum after the fingers lift never turns another page.
        guard event.momentumPhase.isEmpty else { return }

        if event.phase.contains(.began) {
            distance = 0
            vertical = 0
            fired = false
        }
        distance += dx
        vertical += abs(event.scrollingDeltaY)
        // Fingers to the left = next page, like Launchpad.
        if !fired, abs(distance) > Self.threshold, abs(distance) > vertical {
            fired = true
            post(distance < 0 ? 1 : -1)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            distance = 0
            vertical = 0
            fired = false
        }
    }

    private func post(_ step: Int) {
        NotificationCenter.default.post(name: .onboardingSwipe, object: nil, userInfo: ["step": step])
    }
}

// ⌘W closes the guide (agent app: no File menu).
private final class OnboardingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return false
    }
}

// Non-modal window (a modal session would block a Launchpad opened by pinch meanwhile).
private final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var onClose: ((Bool) -> Void)?
    private var finished = false
    private var swipeTracker: OnboardingSwipeTracker?

    init(onClose: @escaping (Bool) -> Void) {
        self.onClose = onClose
        window = OnboardingWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
        super.init()
        window.title = String(localized: "Welcome to AppPad", table: "Onboarding")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self

        let view = OnboardingView(
            prefs: .shared,
            onFinish: { [weak self] in self?.finish() },
            onSkip: { [weak self] in self?.window.performClose(nil) }
        )
        window.contentView = NSHostingView(rootView: view)
        window.setContentSize(OnboardingView.size)
        swipeTracker = OnboardingSwipeTracker(window: window)
    }

    func present() {
        // Centered on the display under the mouse (same screen the panels use).
        if !window.isVisible, let screen = PanelScreen.target() {
            let area = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                          y: area.midY - size.height / 2 + area.height * 0.05))
        }
        NSApp.unhide(nil)
        window.orderFrontRegardless()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        finished = true
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        swipeTracker?.stop()
        swipeTracker = nil
        let callback = onClose
        onClose = nil
        let result = finished
        // After the window is ordered out, so focus hand-off sees no AppPad window.
        DispatchQueue.main.async { callback?(result) }
    }
}
