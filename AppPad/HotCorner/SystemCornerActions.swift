import AppKit
import ApplicationServices
import IOKit.pwr_mgt

// The macOS hot corner actions, run by AppPad (non-sandboxed build).
@MainActor
enum SystemCornerActions {
    static func perform(_ action: HotCornerAction) {
        switch action {
        case .missionControl:
            dock("com.apple.expose.awake", fallbackArguments: [])
        case .applicationWindows:
            dock("com.apple.expose.front.awake", fallbackArguments: ["2"])
        case .desktop:
            dock("com.apple.showdesktop.awake", fallbackArguments: ["1"])
        case .notificationCenter:
            openNotificationCenter()
        case .quickNote:
            newQuickNote()
        case .startScreenSaver:
            startScreenSaver()
        case .disableScreenSaver:
            holdScreenSaverOff()
        case .displaySleep:
            run("/usr/bin/pmset", ["displaysleepnow"])
        case .lockScreen:
            lockScreen()
        case .launchpad, .workflows, .clipboard, .none:
            break
        }
    }

    // Pointer left the corner.
    static func end(_ action: HotCornerAction) {
        if action == .disableScreenSaver { releaseScreenSaverHold() }
    }

    // MARK: - Dock (Mission Control, App Exposé, Show Desktop)

    private typealias DockSendFn = @convention(c) (CFString, UnsafeMutableRawPointer?) -> Void

    // Private CoreDock call (HIServices), the same one other window tools use.
    private static let dockSend: DockSendFn? = {
        guard let symbol = symbol("CoreDockSendNotification",
                                  in: "/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/HIServices")
        else { return nil }
        return unsafeBitCast(symbol, to: DockSendFn.self)
    }()

    // Mission Control.app arguments as fallback: none = Mission Control, "1" = Desktop, "2" = App windows.
    private static func dock(_ notification: String, fallbackArguments: [String]) {
        if let dockSend {
            dockSend(notification as CFString, nil)
            return
        }
        run("/System/Applications/Mission Control.app/Contents/MacOS/Mission Control", fallbackArguments)
    }

    // MARK: - Notification Center / Quick Note (Accessibility)

    // Clicks the menu bar clock, which opens Notification Center.
    private static func openNotificationCenter() {
        guard PasteService.isTrusted else {
            NSSound.beep()
            return
        }
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter")
                .first?.processIdentifier else {
            NSSound.beep()
            return
        }
        let app = AXUIElementCreateApplication(pid)
        guard let bar: AXUIElement = attribute(app, kAXExtrasMenuBarAttribute),
              let items: [AXUIElement] = attribute(bar, kAXChildrenAttribute),
              let clock = items.first(where: { (attribute($0, kAXIdentifierAttribute) as String?) == "com.apple.menuextra.clock" })
        else {
            NSLog("Hot corner: menu bar clock not found")
            NSSound.beep()
            return
        }
        AXUIElementPerformAction(clock, kAXPressAction as CFString)
    }

    // Globe/Fn + Q, the system Quick Note shortcut.
    private static func newQuickNote() {
        guard PasteService.isTrusted else {
            NSSound.beep()
            return
        }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyQ: CGKeyCode = 12
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyQ, keyDown: down)
            event?.flags = .maskSecondaryFn
            event?.post(tap: .cghidEventTap)
        }
    }

    private static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    // MARK: - Screen saver

    private static func startScreenSaver() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { NSLog("Screen saver failed: \(error)") }
        }
    }

    // Idle assertion while the pointer rests in the corner: no screen saver, no display sleep.
    private static var screenSaverHold: IOPMAssertionID?

    private static func holdScreenSaverOff() {
        guard screenSaverHold == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "AppPad hot corner: Disable Screen Saver" as CFString,
            &id)
        if result == kIOReturnSuccess { screenSaverHold = id }
    }

    private static func releaseScreenSaverHold() {
        guard let id = screenSaverHold else { return }
        IOPMAssertionRelease(id)
        screenSaverHold = nil
    }

    // MARK: - Lock screen

    private typealias LockFn = @convention(c) () -> Int32

    // Private login.framework call behind the menu bar "Lock Screen".
    private static let lockNow: LockFn? = {
        guard let symbol = symbol("SACLockScreenImmediate",
                                  in: "/System/Library/PrivateFrameworks/login.framework/Versions/Current/login")
        else { return nil }
        return unsafeBitCast(symbol, to: LockFn.self)
    }()

    private static func lockScreen() {
        if let lockNow {
            _ = lockNow()
        } else {
            run("/usr/bin/pmset", ["displaysleepnow"])   // locks when a password is required after sleep
        }
    }

    // MARK: - Helpers

    private static func symbol(_ name: String, in path: String) -> UnsafeMutableRawPointer? {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
        if let found = dlsym(defaultHandle, name) { return found }
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        return dlsym(handle, name)
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            NSLog("Hot corner action failed: \(error)")
        }
    }
}
