import AppKit
import IOKit

nonisolated enum PinchDirection: Sendable {
    case pinchIn   // thumb + three fingers come together → open
    case spread    // fingers move apart → close
}

// Continuous pinch updates, like an interactive NSGestureRecognizer.
nonisolated struct PinchEvent: Sendable {
    enum Phase: Sendable { case began, changed, ended }
    var phase: Phase
    var direction: PinchDirection
    var progress: CGFloat   // 0...1 toward completing `direction`
    var velocity: CGFloat   // progress per second (> 0 = toward completion)
}

// System-wide four/five-finger pinch read from the private MultitouchSupport framework.
// System gestures are consumed by the Dock, so NSEvent monitors never see them.
// Also reports one-finger taps (on demand): a tap that stops a running scroll is eaten by
// macOS and never becomes a click, so the launcher replays it itself.
// Needs a non-sandboxed build (Developer ID); no extra permission required.
nonisolated final class PinchGestureMonitor: @unchecked Sendable {
    static let shared = PinchGestureMonitor()

    // MARK: - MultitouchSupport ABI

    private typealias DeviceRef = UnsafeMutableRawPointer
    private typealias FrameCallback = @convention(c) (DeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (DeviceRef?, FrameCallback?) -> Void
    private typealias StartFn = @convention(c) (DeviceRef?, Int32) -> Void
    private typealias StopFn = @convention(c) (DeviceRef?) -> Void

    private struct API {
        let createList: CreateListFn
        let register: RegisterFn
        let unregister: RegisterFn
        let start: StartFn
        let stop: StopFn
    }

    // MTTouch layout (64-bit): 96-byte stride; state @20, normalized x/y @32/@36.
    private static let touchStride = 96
    private static let stateOffset = 20
    private static let xOffset = 32
    private static let yOffset = 36
    private static let touchingStates: ClosedRange<Int32> = 4...5   // make-touch, touching

    // Trackpads are ~1.5× wider than tall; scale x so distances are roughly isotropic.
    private static let aspect: Float = 1.5
    private static let minSpread: Float = 0.04
    // Spread ratio → progress: dead zone, then linear up to "full".
    private static let pinchInStart: Float = 0.92
    private static let pinchInFull: Float = 0.55
    private static let spreadStart: Float = 1.08
    private static let spreadFull: Float = 1.60
    // Swipe vs pinch: compare centroid travel with the spread change (both normalized).
    // Any direction: travel beyond this while barely resizing = swipe (Mission Control etc.).
    private static let swipeTravel: Float = 0.08
    private static let swipeResizeRatio: Float = 0.35
    // Sideways (4-finger left/right = Spaces): stricter. A thumb pinch drifts little sideways.
    private static let swipeTravelX: Float = 0.04
    private static let lockResizeRatioX: Float = 0.7    // resize must reach 0.7× sideways drift to lock
    // Already locked but the hand keeps sliding sideways → it was a swipe, roll back.
    private static let abortTravelX: Float = 0.08
    private static let abortResizeRatioX: Float = 0.5
    private static let abortMaxProgress: Float = 0.6
    // One-finger tap: short contact, almost no travel (normalized, aspect-scaled).
    private static let tapMaxDuration: Double = 0.3
    private static let tapMaxTravel: Float = 0.03

    private static let frameCallback: FrameCallback = { device, touches, count, timestamp, _ in
        PinchGestureMonitor.shared.process(device, touches, Int(count), timestamp)
        return 0
    }

    // Multitouch device added / removed (runs on the main run loop).
    private static let deviceCallback: IOServiceMatchingCallback = { _, iterator in
        PinchGestureMonitor.drain(iterator)
        Task { @MainActor in PinchGestureMonitor.shared.scheduleRestart() }
    }

    // MARK: - Gesture state (touched from the multitouch thread)

    private struct Tracking {
        var fingers = 0
        var baseline: Float = 0
        var ratio: Float = 1
        var startX: Float = 0, startY: Float = 0
        var lastX: Float = 0, lastY: Float = 0
        var direction: PinchDirection?
        var rejected = false
        var progress: Float = 0
        var velocity: Float = 0
        var lastTime: Double = 0
        var lastSent: Float = -1
    }

    private struct TapTracking {
        var began = false
        var spoiled = false   // second finger, travel or too long: not a tap
        var startTime: Double = 0
        var startX: Float = 0, startY: Float = 0
    }

    private let lock = NSLock()
    private var tracking: [Int: Tracking] = [:]   // per device
    private var taps: [Int: TapTracking] = [:]    // per device
    private var handler: (@MainActor @Sendable (PinchEvent) -> Void)?
    private var tapHandler: (@MainActor @Sendable () -> Void)?
    private var pinchOn = false   // lock-protected mirrors of the main-thread flags
    private var tapOn = false

    // MARK: - Device state (main thread only)

    private var api: API?
    private var deviceList: CFArray?
    private var devices: [DeviceRef] = []
    private var enabled = false       // pinch
    private var tapEnabled = false
    private var wantsDevices: Bool { enabled || tapEnabled }
    private var observersInstalled = false
    private var notifyPort: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []
    private var restartTask: Task<Void, Never>?

    private init() {}

    var onPinch: (@MainActor @Sendable (PinchEvent) -> Void)? {
        get { lock.withLock { handler } }
        set { lock.withLock { handler = newValue } }
    }

    var onTap: (@MainActor @Sendable () -> Void)? {
        get { lock.withLock { tapHandler } }
        set { lock.withLock { tapHandler = newValue } }
    }

    // Pinch recognition (user setting).
    @MainActor
    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        lock.withLock { pinchOn = on }
        if !on { cancelPinch() }
        updateDevices()
    }

    // Tap reporting (only while the launcher is on screen).
    @MainActor
    func setTapEnabled(_ on: Bool) {
        guard on != tapEnabled else { return }
        tapEnabled = on
        lock.withLock {
            tapOn = on
            taps = [:]
        }
        updateDevices()
    }

    @MainActor
    private func updateDevices() {
        if wantsDevices {
            installObservers()
            startDevices()
        } else {
            restartTask?.cancel()
            stopDevices()
        }
    }

    // MARK: - Devices

    @MainActor
    private func startDevices() {
        guard devices.isEmpty else { return }
        guard let api = api ?? Self.loadAPI() else {
            NSLog("PinchGestureMonitor: MultitouchSupport unavailable")
            return
        }
        self.api = api
        guard let list = api.createList()?.takeRetainedValue() else { return }
        deviceList = list
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            api.register(device, Self.frameCallback)
            api.start(device, 0)
            devices.append(device)
        }
    }

    @MainActor
    private func stopDevices() {
        if let api {
            for device in devices {
                api.unregister(device, Self.frameCallback)
                api.stop(device)
            }
        }
        devices = []
        deviceList = nil   // release after stopping
        lock.withLock { taps = [:] }
        cancelPinch()
    }

    // A gesture in flight would leave the panel half visible → cancel it.
    @MainActor
    private func cancelPinch() {
        let (active, handler) = lock.withLock { () -> (PinchDirection?, (@MainActor @Sendable (PinchEvent) -> Void)?) in
            let active = tracking.values.first { $0.direction != nil && !$0.rejected }?.direction
            tracking = [:]
            return (active, self.handler)
        }
        if let active, let handler {
            handler(PinchEvent(phase: .ended, direction: active, progress: 0, velocity: -10))
        }
    }

    // Trackpad plugged in / removed, or wake from sleep → rebuild the device list.
    @MainActor
    private func scheduleRestart() {
        guard wantsDevices else { return }
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled, self.wantsDevices else { return }
            self.stopDevices()
            self.startDevices()
        }
    }

    @MainActor
    private func installObservers() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                let monitor = PinchGestureMonitor.shared
                monitor.restartTask?.cancel()
                monitor.stopDevices()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in PinchGestureMonitor.shared.scheduleRestart() }
        }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notifyPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           IONotificationPortGetRunLoopSource(port).takeUnretainedValue(),
                           .defaultMode)
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, type, IOServiceMatching("AppleMultitouchDevice"), Self.deviceCallback, nil, &iterator)
            guard result == KERN_SUCCESS else { continue }
            Self.drain(iterator)   // arms the notification
            iterators.append(iterator)
        }
    }

    private static func drain(_ iterator: io_iterator_t) {
        var object = IOIteratorNext(iterator)
        while object != 0 {
            IOObjectRelease(object)
            object = IOIteratorNext(iterator)
        }
    }

    private static func loadAPI() -> API? {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }
        guard let createList = symbol("MTDeviceCreateList", as: CreateListFn.self),
              let register = symbol("MTRegisterContactFrameCallback", as: RegisterFn.self),
              let unregister = symbol("MTUnregisterContactFrameCallback", as: RegisterFn.self),
              let start = symbol("MTDeviceStart", as: StartFn.self),
              let stop = symbol("MTDeviceStop", as: StopFn.self)
        else { return nil }
        return API(createList: createList, register: register, unregister: unregister, start: start, stop: stop)
    }

    // MARK: - Recognition (multitouch thread)

    private func process(_ device: DeviceRef?, _ touches: UnsafeMutableRawPointer?, _ count: Int, _ time: Double) {
        // Centroid of fingers that are actually on the surface.
        var n = 0
        var sx: Float = 0, sy: Float = 0
        if let touches {
            for i in 0..<count {
                let t = touches + i * Self.touchStride
                guard Self.touchingStates.contains(t.load(fromByteOffset: Self.stateOffset, as: Int32.self)) else { continue }
                sx += t.load(fromByteOffset: Self.xOffset, as: Float.self) * Self.aspect
                sy += t.load(fromByteOffset: Self.yOffset, as: Float.self)
                n += 1
            }
        }

        // Mean distance from the centroid.
        var cx: Float = 0, cy: Float = 0, spread: Float = 0
        if n >= 4, let touches {
            cx = sx / Float(n)
            cy = sy / Float(n)
            for i in 0..<count {
                let t = touches + i * Self.touchStride
                guard Self.touchingStates.contains(t.load(fromByteOffset: Self.stateOffset, as: Int32.self)) else { continue }
                let dx = t.load(fromByteOffset: Self.xOffset, as: Float.self) * Self.aspect - cx
                let dy = t.load(fromByteOffset: Self.yOffset, as: Float.self) - cy
                spread += (dx * dx + dy * dy).squareRoot()
            }
            spread /= Float(n)
        }

        let key = Int(bitPattern: device)
        typealias PinchOutput = (PinchEvent, @MainActor @Sendable (PinchEvent) -> Void)
        let (output, tap) = lock.withLock { () -> (PinchOutput?, (@MainActor @Sendable () -> Void)?) in
            var output: PinchOutput?
            if pinchOn {
                var s = tracking[key] ?? Tracking()
                let event = Self.step(&s, n: n, cx: cx, cy: cy, spread: spread, time: time)
                tracking[key] = s
                if let event, let handler { output = (event, handler) }
            }
            var tap: (@MainActor @Sendable () -> Void)?
            if tapOn {
                var t = taps[key] ?? TapTracking()
                // Single finger: the centroid is that finger.
                if Self.stepTap(&t, n: n, x: sx, y: sy, time: time) { tap = tapHandler }
                taps[key] = t
            }
            return (output, tap)
        }

        // FIFO on the main queue so began/changed/ended stay ordered.
        if let output {
            let (event, handler) = output
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler(event) }
            }
        }
        if let tap {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { tap() }
            }
        }
    }

    // One frame of the tap recognizer; true when a one-finger tap just finished (finger lifted).
    private static func stepTap(_ t: inout TapTracking, n: Int, x: Float, y: Float, time: Double) -> Bool {
        if n == 0 {
            let isTap = t.began && !t.spoiled && time - t.startTime <= tapMaxDuration
            t = TapTracking()
            return isTap
        }
        if !t.began {
            t.began = true
            t.startTime = time
            t.startX = x; t.startY = y
        }
        if n > 1 {
            t.spoiled = true
        } else if !t.spoiled {
            let travel = ((x - t.startX) * (x - t.startX) + (y - t.startY) * (y - t.startY)).squareRoot()
            if travel > tapMaxTravel || time - t.startTime > tapMaxDuration { t.spoiled = true }
        }
        return false
    }

    // One frame of the recognizer; returns an event to publish, if any.
    private static func step(_ s: inout Tracking, n: Int, cx: Float, cy: Float, spread: Float, time: Double) -> PinchEvent? {
        // Fingers lifted → end the gesture.
        guard (4...5).contains(n) else {
            var ended: PinchEvent?
            if let direction = s.direction, !s.rejected {
                ended = PinchEvent(phase: .ended, direction: direction,
                                   progress: CGFloat(s.progress), velocity: CGFloat(s.velocity))
            }
            s = Tracking()
            return ended
        }

        // New contact.
        if s.fingers == 0 {
            s.fingers = n
            s.baseline = spread
            s.startX = cx; s.startY = cy
            s.lastX = cx; s.lastY = cy
            s.lastTime = time
            if spread < minSpread { s.rejected = true }
            return nil
        }

        // Finger added / removed mid-gesture: keep ratio and travel continuous.
        if n != s.fingers {
            s.fingers = n
            if spread > 0 { s.baseline = spread / max(s.ratio, 0.01) }
            s.startX += cx - s.lastX
            s.startY += cy - s.lastY
            s.lastX = cx; s.lastY = cy
            return nil
        }
        if s.rejected { return nil }

        let ratio = spread / s.baseline
        s.ratio = ratio
        s.lastX = cx; s.lastY = cy

        // Centroid drift (sideways and total) vs. how much the hand changed size.
        let dx = abs(cx - s.startX)
        let dy = cy - s.startY
        let travel = (dx * dx + dy * dy).squareRoot()
        let resize = abs(spread - s.baseline)

        var began = false
        if s.direction == nil {
            // Moving more than resizing → 4-finger swipe, never a pinch for this contact.
            if (dx > swipeTravelX && resize < dx * lockResizeRatioX)
                || (travel > swipeTravel && resize < travel * swipeResizeRatio) {
                s.rejected = true
                return nil
            }
            let candidate: PinchDirection? = ratio < pinchInStart ? .pinchIn
                : (ratio > spreadStart ? .spread : nil)
            // Lock only once the size change clearly outweighs sideways drift.
            guard let candidate, resize >= dx * lockResizeRatioX else {
                s.lastTime = time
                return nil
            }
            s.direction = candidate
            began = true
        } else if let direction = s.direction, s.progress < abortMaxProgress,
                  dx > abortTravelX, resize < dx * abortResizeRatioX {
            // Locked early, but the hand kept sliding sideways: swipe after all → roll back.
            s.rejected = true
            return PinchEvent(phase: .ended, direction: direction, progress: 0, velocity: -10)
        }

        // Direction is locked; reversing the fingers brings progress back to 0.
        let raw: Float = s.direction == .pinchIn
            ? (pinchInStart - ratio) / (pinchInStart - pinchInFull)
            : (ratio - spreadStart) / (spreadFull - spreadStart)
        let progress = min(max(raw, 0), 1)

        let dt = Float(time - s.lastTime)
        if dt > 0.001 {
            let instant = (progress - s.progress) / dt
            s.velocity = s.velocity * 0.6 + instant * 0.4   // light smoothing
        }
        s.lastTime = time
        s.progress = progress

        guard let direction = s.direction else { return nil }
        if began {
            s.lastSent = progress
            return PinchEvent(phase: .began, direction: direction, progress: CGFloat(progress), velocity: 0)
        }
        guard abs(progress - s.lastSent) > 0.003 else { return nil }
        s.lastSent = progress
        return PinchEvent(phase: .changed, direction: direction,
                          progress: CGFloat(progress), velocity: CGFloat(s.velocity))
    }
}
