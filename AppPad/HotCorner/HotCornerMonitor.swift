import AppKit

// Screen corner that can run an action.
nonisolated enum HotCorner: String, CaseIterable, Codable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var title: String {
        switch self {
        case .topLeft: return String(localized: "Top left", table: "HotCorner")
        case .topRight: return String(localized: "Top right", table: "HotCorner")
        case .bottomLeft: return String(localized: "Bottom left", table: "HotCorner")
        case .bottomRight: return String(localized: "Bottom right", table: "HotCorner")
        }
    }

    // com.apple.dock key part (wvous-tl-corner …).
    var dockCode: String {
        switch self {
        case .topLeft: return "tl"
        case .topRight: return "tr"
        case .bottomLeft: return "bl"
        case .bottomRight: return "br"
        }
    }

    var isTop: Bool { self == .topLeft || self == .topRight }
    var isLeft: Bool { self == .topLeft || self == .bottomLeft }

    // Corner point of a screen frame (Cocoa coordinates, origin bottom-left).
    func point(in frame: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? frame.minX : frame.maxX, y: isTop ? frame.maxY : frame.minY)
    }
}

// AppPad features first, then the macOS hot corner actions (same order as System Settings,
// without Launchpad), then none.
nonisolated enum HotCornerAction: String, CaseIterable, Codable, Sendable {
    case launchpad, workflows, clipboard
    case missionControl, applicationWindows, desktop, notificationCenter, quickNote
    case startScreenSaver, disableScreenSaver, displaySleep, lockScreen
    case none

    static let appPadActions: [HotCornerAction] = [.launchpad, .workflows, .clipboard]
    static let systemActions: [HotCornerAction] = [
        .missionControl, .applicationWindows, .desktop, .notificationCenter, .quickNote,
        .startScreenSaver, .disableScreenSaver, .displaySleep, .lockScreen,
    ]

    var isSystem: Bool { Self.systemActions.contains(self) }

    // Pressed through the menu bar / synthesized keys.
    var needsAccessibility: Bool { self == .notificationCenter || self == .quickNote }

    var title: String {
        switch self {
        case .launchpad: return String(localized: "AppPad")
        case .workflows: return String(localized: "Workflows")
        case .clipboard: return String(localized: "Clipboard")
        case .missionControl: return String(localized: "Mission Control", table: "HotCorner")
        case .applicationWindows: return String(localized: "Application Windows", table: "HotCorner")
        case .desktop: return String(localized: "Desktop", table: "HotCorner")
        case .notificationCenter: return String(localized: "Notification Center", table: "HotCorner")
        case .quickNote: return String(localized: "Quick Note", table: "HotCorner")
        case .startScreenSaver: return String(localized: "Start Screen Saver", table: "HotCorner")
        case .disableScreenSaver: return String(localized: "Disable Screen Saver", table: "HotCorner")
        case .displaySleep: return String(localized: "Put Display to Sleep", table: "HotCorner")
        case .lockScreen: return String(localized: "Lock Screen", table: "HotCorner")
        case .none: return "–"
        }
    }
}

// Keys that must be held for a corner to fire (chosen by holding them in the menu, like macOS).
nonisolated struct HotCornerModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let control = HotCornerModifiers(rawValue: 1 << 0)
    static let option = HotCornerModifiers(rawValue: 1 << 1)
    static let shift = HotCornerModifiers(rawValue: 1 << 2)
    static let command = HotCornerModifiers(rawValue: 1 << 3)

    // Every non-empty combination (menu alternates).
    static let combinations: [HotCornerModifiers] = (1...15).map { HotCornerModifiers(rawValue: $0) }

    init(rawValue: Int) { self.rawValue = rawValue & 0xF }

    init(_ flags: NSEvent.ModifierFlags) {
        var value: HotCornerModifiers = []
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.command) { value.insert(.command) }
        self = value
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.control) { flags.insert(.control) }
        if contains(.option) { flags.insert(.option) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.command) { flags.insert(.command) }
        return flags
    }

    // Apple order: ⌃⌥⇧⌘.
    var symbols: String {
        (contains(.control) ? "⌃" : "") + (contains(.option) ? "⌥" : "")
            + (contains(.shift) ? "⇧" : "") + (contains(.command) ? "⌘" : "")
    }
}

nonisolated struct HotCornerSetting: Codable, Equatable, Sendable {
    var action: HotCornerAction = .none
    var modifiers: HotCornerModifiers = []

    init(action: HotCornerAction = .none, modifiers: HotCornerModifiers = []) {
        self.action = action
        self.modifiers = modifiers
    }

    var isSet: Bool { action != .none }

    // Menu / button title, e.g. "⌃⌘ Mission Control".
    var title: String {
        guard isSet, !modifiers.isEmpty else { return action.title }
        return modifiers.symbols + " " + action.title
    }

    private enum CodingKeys: String, CodingKey {
        case action, modifiers
        case requiresCommand   // v1 (⌘ only), read for migration
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        action = try c.decodeIfPresent(HotCornerAction.self, forKey: .action) ?? .none
        if let raw = try c.decodeIfPresent(Int.self, forKey: .modifiers) {
            modifiers = HotCornerModifiers(rawValue: raw)
        } else {
            modifiers = (try c.decodeIfPresent(Bool.self, forKey: .requiresCommand) ?? false) ? .command : []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(action, forKey: .action)
        try c.encode(modifiers.rawValue, forKey: .modifiers)
    }
}

// All four corners; missing entries are off.
nonisolated struct HotCornerConfig: Codable, Equatable, Sendable {
    var corners: [String: HotCornerSetting] = [:]   // HotCorner raw value → setting

    subscript(corner: HotCorner) -> HotCornerSetting {
        get { corners[corner.rawValue] ?? HotCornerSetting() }
        set { corners[corner.rawValue] = newValue.isSet ? newValue : nil }
    }

    var isActive: Bool { HotCorner.allCases.contains { self[$0].isSet } }

    func uses(_ predicate: (HotCornerAction) -> Bool) -> Bool {
        HotCorner.allCases.contains { predicate(self[$0].action) }
    }
}

// Watches the pointer and reports when it reaches an outer screen corner.
// Mouse-moved monitoring needs no Accessibility permission. While an AppPad window is key
// (its own events don't reach the global monitor), the pointer is polled instead.
@MainActor
final class HotCornerMonitor {
    static let shared = HotCornerMonitor()

    var onTrigger: ((HotCornerAction) -> Void)?
    // Pointer left a corner whose action ran (Disable Screen Saver lasts until then).
    var onLeave: ((HotCornerAction) -> Void)?

    // Distance from both edges that still counts as "in the corner".
    private static let hitSize: CGFloat = 3
    // Pointer must move this far away before the corner can fire again.
    private static let rearmDistance: CGFloat = 10
    private static let pollInterval: TimeInterval = 1.0 / 30

    private var config = HotCornerConfig()
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    // Corner the pointer is in; done = handled (action ran, or there is none).
    private var current: (corner: HotCorner, point: CGPoint)?
    private var done = false
    private var firedAction: HotCornerAction?

    private init() {}

    func apply(_ config: HotCornerConfig) {
        if config != self.config {
            leaveCorner()
            self.config = config
        }
        config.isActive ? start() : stop()
    }

    // MARK: - Monitoring

    private var isRunning: Bool { !monitors.isEmpty }

    private func start() {
        guard !isRunning else { return }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }) { monitors.append(global) }
        // Modifier pressed while already resting in the corner (delivered only with Accessibility).
        if let flags = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }) { monitors.append(flags) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .flagsChanged], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.check() }
            return event
        }) { monitors.append(local) }

        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
            NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification,
        ]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Next run loop: key state settles after the notification.
                DispatchQueue.main.async { self?.updatePolling() }
            })
        }
        updatePolling()
    }

    private func stop() {
        leaveCorner()
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers = []
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // Poll only while one of AppPad's windows is key or AppPad is active.
    private func updatePolling() {
        let needed = isRunning && (NSApp.isActive || NSApp.windows.contains { $0.isVisible && $0.isKeyWindow })
        if needed, pollTimer == nil {
            let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            timer.tolerance = Self.pollInterval / 2
            RunLoop.main.add(timer, forMode: .common)
            pollTimer = timer
        } else if !needed {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    // MARK: - Corner detection

    private func check() {
        let point = NSEvent.mouseLocation
        if let active = current {
            let near = abs(point.x - active.point.x) <= Self.rearmDistance
                && abs(point.y - active.point.y) <= Self.rearmDistance
            if near {
                if !done { fire(active.corner) }
                return
            }
            leaveCorner()
        }
        guard let hit = corner(at: point) else { return }
        current = hit
        done = false
        fire(hit.corner)
    }

    private func leaveCorner() {
        if let action = firedAction { onLeave?(action) }
        current = nil
        done = false
        firedAction = nil
    }

    private func fire(_ corner: HotCorner) {
        let setting = config[corner]
        guard setting.isSet else {
            done = true
            return
        }
        // Stays armed: pressing the keys while still in the corner fires it.
        let held = HotCornerModifiers(NSEvent.modifierFlags)
        guard held.isSuperset(of: setting.modifiers) else { return }
        // Dragging something into the corner is not a trigger.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        done = true
        firedAction = setting.action
        onTrigger?(setting.action)
    }

    // Outer corner of a display under the pointer (corners shared with another display are skipped).
    private func corner(at point: CGPoint) -> (corner: HotCorner, point: CGPoint)? {
        let frames = NSScreen.screens.map(\.frame)
        for (index, frame) in frames.enumerated() {
            for corner in HotCorner.allCases {
                let c = corner.point(in: frame)
                guard abs(point.x - c.x) <= Self.hitSize, abs(point.y - c.y) <= Self.hitSize else { continue }
                let others = frames.enumerated().filter { $0.offset != index }.map(\.element)
                guard isOuter(corner, at: c, others: others) else { continue }
                return (corner, c)
            }
        }
        return nil
    }

    // The pointer stops here: no other display continues past the corner sideways, up/down or diagonally.
    private func isOuter(_ corner: HotCorner, at c: CGPoint, others: [CGRect]) -> Bool {
        let dx: CGFloat = corner.isLeft ? -1 : 1
        let dy: CGFloat = corner.isTop ? 1 : -1
        let probes = [
            CGPoint(x: c.x + dx * 2, y: c.y - dy * 1),
            CGPoint(x: c.x - dx * 1, y: c.y + dy * 2),
            CGPoint(x: c.x + dx * 2, y: c.y + dy * 2),
        ]
        return !others.contains { frame in probes.contains { frame.contains($0) } }
    }
}

// Hot corners set in System Settings › Desktop & Dock (both would fire).
enum SystemHotCorners {
    private static let dockDomain = "com.apple.dock" as CFString

    // Corners with a system action (0 and 1 mean none).
    static func occupied() -> Set<HotCorner> {
        CFPreferencesAppSynchronize(dockDomain)
        return Set(HotCorner.allCases.filter { corner in
            let key = "wvous-\(corner.dockCode)-corner" as CFString
            let value = CFPreferencesCopyAppValue(key, dockDomain) as? Int ?? 0
            return value > 1
        })
    }

    static func openSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.Desktop-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.dock",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
