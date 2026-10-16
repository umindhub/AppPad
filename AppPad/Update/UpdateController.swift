import AppKit
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

    private var controller: SPUStandardUpdaterController?
    private var updater: SPUUpdater? { controller?.updater }
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
        guard isSupported, controller == nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        controller.startUpdater()
        let updater = controller.updater
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
        guard let controller else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
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

extension UpdateController: @preconcurrency SPUUpdaterDelegate {
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

extension UpdateController: @preconcurrency SPUStandardUserDriverDelegate {
    // Menu-bar app: let Sparkle show scheduled-update alerts without stealing focus.
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        true
    }
}
