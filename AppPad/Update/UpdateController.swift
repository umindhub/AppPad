import AppKit
import Carbon.HIToolbox
import Combine
import Sparkle

// Sparkle updater plus a daily check at a user-set time (Settings › General › Updates).
// Sparkle's own interval timer is only a weekly fallback; the daily slot is driven here.
// Found updates download silently and install once no panel / Settings is on screen,
// then AppPad relaunches without opening Launchpad.
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    // Dev builds never update (own bundle id, no feed).
    let isSupported = AppEnvironment.current != .dev

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var lastCheckDate: Date?
    @Published private(set) var installPending = false

    // True while nothing is on screen; set by AppDelegate.
    var isIdle: () -> Bool = { true }
    // "Up to date" notice closed; AppDelegate hands focus back to the previous app.
    var onNoticeClosed: (() -> Void)?
    var isShowingNotice: Bool { userDriver?.isShowingNotice == true }

    private var updater: SPUUpdater?
    private var userDriver: UpdateUserDriver?
    private var enabled = false
    private var minutes = Preferences.autoUpdateMinutesDefault
    private var lastAttempt: Date?
    private var scheduleTask: Task<Void, Never>?
    private var installTask: Task<Void, Never>?
    private var prefsTask: Task<Void, Never>?
    private var pendingInstall: (() -> Void)?
    private var canCheckObservation: NSKeyValueObservation?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private enum Key {
        static let lastSuccess = "autoUpdate.lastSuccessfulCheck"
        static let relaunchMarker = "autoUpdate.relaunchMarker"
    }

    private static let catchUpDelay: TimeInterval = 45          // after launch / wake: let the network come up
    private static let retryDelay: TimeInterval = 30 * 60       // failed or busy check
    private static let fallbackInterval: TimeInterval = 7 * 24 * 3600
    private static let idlePoll: Duration = .seconds(5)

    func start() {
        guard isSupported, updater == nil else { return }
        // Own user driver: Sparkle's standard UI except the modal "up to date" alert.
        let driver = UpdateUserDriver(hostBundle: .main, delegate: self)
        driver.onNoticeClosed = { [weak self] in self?.onNoticeClosed?() }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do {
            try updater.start()
        } catch {
            NSLog("Sparkle updater failed to start: \(error)")
            return
        }
        userDriver = driver
        self.updater = updater
        updater.updateCheckInterval = Self.fallbackInterval
        lastCheckDate = updater.lastUpdateCheckDate
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            Task { @MainActor [weak self] in self?.canCheckForUpdates = value }
        }
        applyPreferences()
        observeEvents()
    }

    // Settings / menu bar: user-initiated check with Sparkle's own UI.
    func checkForUpdates() {
        guard let updater else { return }
        if userDriver?.bringNoticeToFront() == true { return }
        NSApp.activate()
        updater.checkForUpdates()
    }

    // Settings › "Restart to Update" while an update waits for idle.
    func installNow() {
        guard let install = pendingInstall else { return }
        finishInstall(install)
    }

    // Launch after a Sparkle relaunch: AppDelegate must not open Launchpad.
    static func consumeRelaunchMarker() -> Bool {
        let defaults = UserDefaults.standard
        guard let date = defaults.object(forKey: Key.relaunchMarker) as? Date else { return false }
        defaults.removeObject(forKey: Key.relaunchMarker)
        return abs(Date().timeIntervalSince(date)) < 600
    }

    // MARK: - Preferences

    private func applyPreferences() {
        guard let updater else { return }
        let prefs = Preferences.shared
        let changed = prefs.autoUpdateEnabled != enabled || prefs.autoUpdateMinutes != minutes
        enabled = prefs.autoUpdateEnabled
        minutes = prefs.autoUpdateMinutes
        if updater.automaticallyChecksForUpdates != enabled { updater.automaticallyChecksForUpdates = enabled }
        if updater.automaticallyDownloadsUpdates != enabled { updater.automaticallyDownloadsUpdates = enabled }
        if changed || scheduleTask == nil { reschedule() }
    }

    private func observeEvents() {
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        // Debounced: the time picker posts a change per step.
        add(center, .preferencesDidChange) { [weak self] in
            self?.prefsTask?.cancel()
            self?.prefsTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                self?.applyPreferences()
            }
        }
        // Wall clock moved or the Mac woke up: the pending sleep may be off.
        add(workspace, NSWorkspace.didWakeNotification) { [weak self] in self?.reschedule() }
        add(center, .NSSystemClockDidChange) { [weak self] in self?.reschedule() }
        add(center, .NSSystemTimeZoneDidChange) { [weak self] in self?.reschedule() }
        add(center, .NSCalendarDayChanged) { [weak self] in self?.reschedule() }
    }

    private func add(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        observers.append((center, token))
    }

    // MARK: - Daily schedule

    private var lastSuccess: Date {
        UserDefaults.standard.object(forKey: Key.lastSuccess) as? Date ?? .distantPast
    }

    private var slotComponents: DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60, second: 0)
    }

    // Most recent slot at or before `date`.
    private func previousSlot(_ date: Date) -> Date? {
        Calendar.current.nextDate(after: date.addingTimeInterval(1), matching: slotComponents,
                                  matchingPolicy: .nextTime, direction: .backward)
    }

    private func nextSlot(_ date: Date) -> Date? {
        Calendar.current.nextDate(after: date, matching: slotComponents, matchingPolicy: .nextTime)
    }

    private func reschedule() {
        scheduleTask?.cancel()
        scheduleTask = nil
        guard updater != nil, enabled else { return }
        let now = Date()
        let fireDate: Date
        let onTime: Bool
        if let previous = previousSlot(now), lastSuccess < previous {
            // Today's slot missed (asleep / off / failed): catch up, then retry every 30 min.
            if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.retryDelay {
                fireDate = lastAttempt.addingTimeInterval(Self.retryDelay)
            } else {
                fireDate = now.addingTimeInterval(Self.catchUpDelay)
            }
            onTime = false
        } else if let next = nextSlot(now) {
            fireDate = next
            onTime = true
        } else {
            return
        }
        scheduleTask = Task { [weak self] in
            // ContinuousClock keeps counting during system sleep.
            try? await Task.sleep(for: .seconds(max(fireDate.timeIntervalSinceNow, 0)), tolerance: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            // Woke from sleep past the slot: give the network a moment first.
            if onTime, Date().timeIntervalSince(fireDate) > 60 {
                try? await Task.sleep(for: .seconds(Self.catchUpDelay))
                guard !Task.isCancelled else { return }
            }
            self.runScheduledCheck()
        }
    }

    private func runScheduledCheck() {
        scheduleTask = nil
        guard let updater, enabled else { return }
        lastAttempt = Date()
        // Busy (user check or install in progress): the retry slot picks it up.
        if updater.canCheckForUpdates { updater.checkForUpdatesInBackground() }
        reschedule()
    }

    // MARK: - Install when idle

    private func installWhenIdle() {
        installTask?.cancel()
        installTask = Task { [weak self] in
            var idleTicks = 0
            while idleTicks < 2 {
                try? await Task.sleep(for: Self.idlePoll)
                guard !Task.isCancelled, let self else { return }
                idleTicks = self.isIdle() ? idleTicks + 1 : 0
            }
            guard let self, let install = self.pendingInstall else { return }
            self.finishInstall(install)
        }
    }

    private func finishInstall(_ install: () -> Void) {
        installTask?.cancel()
        installTask = nil
        pendingInstall = nil
        installPending = false
        install()
    }

    // nil or "no update found" (SUNoUpdateError = 1001) both count as a completed check.
    private static func isSuccess(_ error: (any Error)?) -> Bool {
        guard let error = error as NSError? else { return true }
        return error.domain == SUSparkleErrorDomain && error.code == 1001
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateController: SPUUpdaterDelegate {
    // Beta and Release share the bundle id and the feed; Beta also takes beta-channel items.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        AppEnvironment.current == .beta ? ["beta"] : []
    }

    // Silent download finished: install on our own terms instead of waiting for quit
    // (a menu-bar app practically never quits).
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        pendingInstall = immediateInstallHandler
        installPending = true
        installWhenIdle()
        return true
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        UserDefaults.standard.set(Date(), forKey: Key.relaunchMarker)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastCheckDate = updater.lastUpdateCheckDate
        if Self.isSuccess(error) {
            UserDefaults.standard.set(Date(), forKey: Key.lastSuccess)
            lastAttempt = nil
        }
        reschedule()
    }
}

// MARK: - SPUStandardUserDriverDelegate

extension UpdateController: SPUStandardUserDriverDelegate {
    // Menu-bar app: let Sparkle show scheduled-update alerts without stealing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }
}

// MARK: - User driver

// Forwards to SPUStandardUserDriver, except "no update found": Sparkle shows that as an
// app-modal NSAlert (runModal), which blocks key events to the panels (⌘1 paste etc.).
// Ours is a plain panel with an OK pill that counts down and closes itself.
final class UpdateUserDriver: NSObject, SPUUserDriver {
    var onNoticeClosed: (() -> Void)?
    var isShowingNotice: Bool { notice != nil }

    private let standard: SPUStandardUserDriver
    private var notice: UpdateNoticeWindow?

    init(hostBundle: Bundle, delegate: SPUStandardUserDriverDelegate) {
        standard = SPUStandardUserDriver(hostBundle: hostBundle, delegate: delegate)
        super.init()
    }

    @discardableResult
    func bringNoticeToFront() -> Bool {
        guard let notice else { return false }
        NSApp.activate()
        notice.makeKeyAndOrderFront(nil)
        return true
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        // Closes the "Checking for updates…" window (nothing else is up at this point).
        standard.dismissUpdateInstallation()
        notice?.dismiss()
        let nsError = error as NSError
        let reasonValue = (nsError.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value ?? 0
        let reason = SPUNoUpdateFoundReason(rawValue: reasonValue)
        // Countdown only for "you're on the latest"; other reasons (system too old…) stay until OK.
        let isLatest = reason == .onLatestVersion || reason == .onNewerThanLatestVersion
        let window = UpdateNoticeWindow(
            title: nsError.localizedDescription,
            message: nsError.localizedRecoverySuggestion ?? "",
            countdown: isLatest ? UpdateNoticeWindow.countdownDuration : nil
        )
        window.onClose = { [weak self, weak window] in
            guard let self else { return }
            if self.notice === window { self.notice = nil }
            acknowledgement()
            self.onNoticeClosed?()
        }
        notice = window
        window.present()
    }

    func showUpdateInFocus() {
        if bringNoticeToFront() { return }
        (standard as SPUUserDriver).showUpdateInFocus?()
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }

    // MARK: Forwarded

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        standard.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showUpdateFound(with: appcastItem, state: state, reply: reply)
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        standard.showReady(toInstallAndRelaunch: reply)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                              retryTerminatingApplication: @escaping () -> Void) {
        standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated,
                                      retryTerminatingApplication: retryTerminatingApplication)
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        standard.showUpdateInstalledAndRelaunched(relaunched, acknowledgement: acknowledgement)
    }
}

// MARK: - "Up to date" notice

// Non-modal alert-style panel: app icon, title, message and an OK pill.
// Return / Esc / Space or a click on the pill closes it at once.
final class UpdateNoticeWindow: NSPanel {
    static let countdownDuration: TimeInterval = 6

    var onClose: (() -> Void)?

    private let pill: CountdownPillButton
    private var didClose = false
    private static let contentWidth: CGFloat = 260

    init(title: String, message: String, countdown: TimeInterval?) {
        pill = CountdownPillButton(title: String(localized: "OK"), duration: countdown)
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + 40, height: 200),
                   styleMask: [.titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false   // stays while the user clicks into another app
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        animationBehavior = .alertPanel
        pill.onPress = { [weak self] in self?.dismiss() }
        buildContent(title: title, message: message)
    }

    private func buildContent(title: String, message: String) {
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.alignment = .center

        let messageLabel = NSTextField(wrappingLabelWithString: message)
        messageLabel.font = .systemFont(ofSize: 11)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.isHidden = message.isEmpty

        pill.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [icon, titleLabel, messageLabel, pill])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(12, after: icon)
        stack.setCustomSpacing(16, after: messageLabel.isHidden ? titleLabel : messageLabel)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 20, bottom: 18, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            icon.widthAnchor.constraint(equalToConstant: 64),
            icon.heightAnchor.constraint(equalToConstant: 64),
            titleLabel.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            messageLabel.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            pill.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            pill.heightAnchor.constraint(equalToConstant: 28),
        ])
        contentView = root
        setContentSize(root.fittingSize)
    }

    override var canBecomeKey: Bool { true }

    // Upper middle of the target display, like a system alert.
    func present() {
        if let screen = PanelScreen.target() {
            let visible = screen.visibleFrame
            let size = frame.size
            setFrameOrigin(NSPoint(x: (visible.midX - size.width / 2).rounded(),
                                   y: (visible.minY + visible.height * 0.62 - size.height / 2).rounded()))
        } else {
            center()
        }
        makeKeyAndOrderFront(nil)
        pill.start { [weak self] in self?.dismiss() }
    }

    func dismiss() {
        guard !didClose else { return }
        didClose = true
        pill.stop()
        orderOut(nil)
        onClose?()
        onClose = nil
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Space, kVK_Escape:
            dismiss()
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }
}

// Accent pill with a centered label. With a duration, the accent fill shrinks from both
// ends toward the middle; the label is accent-colored over the track and white over the fill.
final class CountdownPillButton: NSView {
    var onPress: (() -> Void)?

    private let title: String
    private let duration: TimeInterval?
    private var startTime: CFTimeInterval = 0
    private var remaining: CGFloat = 1
    private var isPressed = false
    private var link: CADisplayLink?
    private var onFinish: (() -> Void)?

    init(title: String, duration: TimeInterval?) {
        self.title = title
        self.duration = duration
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func start(onFinish: @escaping () -> Void) {
        guard duration != nil, link == nil else { return }
        self.onFinish = onFinish
        startTime = CACurrentMediaTime()
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)   // keeps running during menu tracking
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        onFinish = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard let duration else { return }
        let elapsed = CACurrentMediaTime() - startTime
        remaining = CGFloat(max(0, 1 - elapsed / duration))
        needsDisplay = true
        if remaining <= 0 {
            let finish = onFinish
            stop()
            finish?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let pill = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        let accent = NSColor.controlAccentColor
        let fillColor = isPressed ? (accent.shadow(withLevel: 0.2) ?? accent) : accent

        NSGraphicsContext.saveGraphicsState()
        pill.addClip()
        accent.withAlphaComponent(0.18).setFill()
        rect.fill()
        let fillWidth = (rect.width * remaining).rounded()
        let fillRect = NSRect(x: rect.midX - fillWidth / 2, y: rect.minY, width: fillWidth, height: rect.height)
        fillColor.setFill()
        fillRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        drawTitle(in: rect, color: accent, clip: nil)
        drawTitle(in: rect, color: .white, clip: fillRect)
    }

    private func drawTitle(in rect: NSRect, color: NSColor, clip: NSRect?) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color,
        ]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        let origin = NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        NSGraphicsContext.saveGraphicsState()
        if let clip { NSBezierPath(rect: clip).addClip() }
        text.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != isPressed {
            isPressed = inside
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        needsDisplay = true
        if inside { onPress?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onPress?()
        return true
    }
}
