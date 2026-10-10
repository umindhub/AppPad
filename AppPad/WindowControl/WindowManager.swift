import AppKit
import ApplicationServices

// Snaps / maximizes / restores / moves the focused window of the frontmost app (Accessibility API).
final class WindowManager {
    static let shared = WindowManager()

    // Called when a shortcut fires without Accessibility permission.
    var onNeedsAccess: (() -> Void)?

    private enum Side { case left, right }

    private enum Placement: Equatable {
        case snap(Side, Int)   // index into fractions
        case maximized
        case free              // moved to another display without snapping
    }

    // Repeated presses cycle ½ → ⅓ → ⅔.
    private static let fractions: [CGFloat] = [1.0 / 2, 1.0 / 3, 2.0 / 3]

    // Per-window state: frame before the first action (for restore) + last applied result.
    private struct Record {
        let window: AXUIElement
        var original: CGRect
        var placement: Placement
        var lastFrame: CGRect
    }

    private var records: [Record] = []
    private static let maxRecords = 64

    private init() {}

    func perform(_ action: WindowAction) {
        guard AXIsProcessTrusted() else {
            PasteService.requestAccess()
            onNeedsAccess?()
            return
        }
        guard let window = focusedWindow(),
              !boolValue(window, "AXFullScreen"),
              isSettable(window, kAXPositionAttribute),
              let frame = windowFrame(window),
              let screen = screenContaining(frame) else {
            NSSound.beep()
            return
        }
        switch action {
        case .snapLeft: snap(window, frame: frame, side: .left, screen: screen)
        case .snapRight: snap(window, frame: frame, side: .right, screen: screen)
        case .maximize: apply(.maximized, rect: Self.visibleArea(screen), to: window, current: frame)
        case .restore: restore(window)
        case .previousDisplay: moveToDisplay(window, frame: frame, from: screen, step: -1)
        case .nextDisplay: moveToDisplay(window, frame: frame, from: screen, step: 1)
        }
    }

    // MARK: - Actions

    private func snap(_ window: AXUIElement, frame: CGRect, side: Side, screen: NSScreen) {
        let area = Self.visibleArea(screen)
        var index = 0
        if let record = activeRecord(for: window, frame: frame), case .snap(side, let i) = record.placement {
            index = (i + 1) % Self.fractions.count
        } else if let i = Self.fractions.indices.first(where: { Self.matches(frame, Self.snapRect(side, $0, in: area)) }) {
            // Already at one of the sizes (e.g. snapped by hand or before a relaunch)
            index = (i + 1) % Self.fractions.count
        }
        apply(.snap(side, index), rect: Self.snapRect(side, index, in: area), to: window, current: frame)
    }

    private func restore(_ window: AXUIElement) {
        guard let i = records.firstIndex(where: { CFEqual($0.window, window) }) else {
            NSSound.beep()
            return
        }
        let record = records.remove(at: i)
        setFrame(record.original, of: window)
    }

    private func moveToDisplay(_ window: AXUIElement, frame: CGRect, from screen: NSScreen, step: Int) {
        // Displays ordered left → right, then bottom → top; wraps around.
        let screens = NSScreen.screens.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
        guard screens.count > 1, let current = screens.firstIndex(of: screen) else {
            NSSound.beep()
            return
        }
        let target = screens[(current + step + screens.count) % screens.count]
        let src = Self.visibleArea(screen)
        let dst = Self.visibleArea(target)

        // Snapped / maximized windows keep their layout on the new display.
        if let record = activeRecord(for: window, frame: frame) {
            switch record.placement {
            case .snap(let side, let i):
                apply(record.placement, rect: Self.snapRect(side, i, in: dst), to: window, current: frame)
                return
            case .maximized:
                apply(.maximized, rect: dst, to: window, current: frame)
                return
            case .free:
                break
            }
        }
        // Free window: keep its size (clamped) and relative center.
        let w = min(frame.width, dst.width)
        let h = min(frame.height, dst.height)
        let cx = dst.minX + (frame.midX - src.minX) / max(src.width, 1) * dst.width
        let cy = dst.minY + (frame.midY - src.minY) / max(src.height, 1) * dst.height
        let x = min(max(cx - w / 2, dst.minX), dst.maxX - w)
        let y = min(max(cy - h / 2, dst.minY), dst.maxY - h)
        apply(.free, rect: CGRect(x: x, y: y, width: w, height: h).integral, to: window, current: frame)
    }

    // Moves the window and updates its record; keeps the original frame while untouched by the user.
    private func apply(_ placement: Placement, rect: CGRect, to window: AXUIElement, current: CGRect) {
        let index = records.firstIndex { CFEqual($0.window, window) }
        var original = current
        if let index, Self.isClose(records[index].lastFrame, current, tolerance: 2) {
            original = records[index].original
        }
        setFrame(rect, of: window)
        let result = windowFrame(window) ?? rect
        let record = Record(window: window, original: original, placement: placement, lastFrame: result)
        if let index {
            records[index] = record
        } else {
            records.append(record)
            if records.count > Self.maxRecords { records.removeFirst() }
        }
    }

    // Record whose last result still matches the window (not moved by the user since).
    private func activeRecord(for window: AXUIElement, frame: CGRect) -> Record? {
        guard let record = records.first(where: { CFEqual($0.window, window) }),
              Self.isClose(record.lastFrame, frame, tolerance: 2) else { return nil }
        return record
    }

    // MARK: - Geometry (AX coordinates: top-left origin at the primary display)

    private static func axRect(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func visibleArea(_ screen: NSScreen) -> CGRect {
        axRect(screen.visibleFrame)
    }

    private static func snapRect(_ side: Side, _ index: Int, in area: CGRect) -> CGRect {
        let width = (area.width * fractions[index]).rounded()
        let x = side == .left ? area.minX : area.maxX - width
        return CGRect(x: x, y: area.minY, width: width, height: area.height)
    }

    // Loose match: apps like Terminal round sizes to their character grid.
    private static func matches(_ frame: CGRect, _ target: CGRect) -> Bool {
        abs(frame.minX - target.minX) <= 6 && abs(frame.minY - target.minY) <= 6
            && abs(frame.width - target.width) <= 24 && abs(frame.height - target.height) <= 40
    }

    private static func isClose(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    // Screen with the largest overlap, else the one nearest to the window center.
    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        let best = screens.max { a, b in
            Self.area(Self.axRect(a.frame).intersection(frame)) < Self.area(Self.axRect(b.frame).intersection(frame))
        }
        if let best, Self.area(Self.axRect(best.frame).intersection(frame)) > 0 { return best }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return screens.min { Self.distance(Self.axRect($0.frame), center) < Self.distance(Self.axRect($1.frame), center) }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func distance(_ rect: CGRect, _ point: CGPoint) -> CGFloat {
        hypot(rect.midX - point.x, rect.midY - point.y)
    }

    // MARK: - AX helpers

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        return uiElement(element, kAXFocusedWindowAttribute) ?? uiElement(element, kAXMainWindowAttribute)
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        guard let origin = axValue(window, kAXPositionAttribute, type: .cgPoint, CGPoint.zero),
              let size = axValue(window, kAXSizeAttribute, type: .cgSize, CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    // Size → position → size: the first size may be clamped by the old display.
    private func setFrame(_ rect: CGRect, of window: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        let app = AXUIElementCreateApplication(pid)
        // Enhanced UI (VoiceOver, some apps) animates frame changes and breaks sizing; turn it off briefly.
        let enhanced = boolValue(app, "AXEnhancedUserInterface")
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }

        var size = rect.size
        var origin = rect.origin
        if let sizeValue = AXValueCreate(.cgSize, &size), let originValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    private func copyValue(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func uiElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axValue<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType, _ initial: T) -> T? {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var result = initial
        return AXValueGetValue(value as! AXValue, type, &result) ? result : nil
    }

    private func boolValue(_ element: AXUIElement, _ attribute: String) -> Bool {
        guard let value = copyValue(element, attribute), CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }
}
