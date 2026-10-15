import AppKit
import Carbon.HIToolbox

// Global hotkeys via Carbon RegisterEventHotKey (no Accessibility permission needed).
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private struct Registration {
        let combo: KeyCombo
        let handler: () -> Void
        var ref: EventHotKeyRef?
    }

    nonisolated private static let signature: OSType = 0x4150_444B // "APDK"

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handlerRef: EventHandlerRef?
    private var suspendCount = 0

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), Self.makeCallback(), 1, &spec, nil, &handlerRef)
    }

    // C callback built in a nonisolated context; Carbon delivers on the main thread.
    nonisolated private static func makeCallback() -> EventHandlerUPP {
        return { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == OSStatus(noErr), hotKeyID.signature == HotKeyCenter.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let id = hotKeyID.id
            MainActor.assumeIsolated {
                HotKeyCenter.shared.fire(id)
            }
            return OSStatus(noErr)
        }
    }

    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> UInt32 {
        let id = nextID
        nextID += 1
        var registration = Registration(combo: combo, handler: handler, ref: nil)
        if suspendCount == 0 {
            registration.ref = install(combo, id: id)
        }
        registrations[id] = registration
        return id
    }

    // False when RegisterEventHotKey failed (e.g. combo taken) or while suspended.
    func isInstalled(_ id: UInt32) -> Bool {
        registrations[id]?.ref != nil
    }

    func unregister(_ id: UInt32) {
        if let ref = registrations.removeValue(forKey: id)?.ref {
            UnregisterEventHotKey(ref)
        }
    }

    // Temporarily release all hotkeys (used while recording a new shortcut).
    func suspend() {
        suspendCount += 1
        guard suspendCount == 1 else { return }
        for (id, var registration) in registrations {
            if let ref = registration.ref { UnregisterEventHotKey(ref) }
            registration.ref = nil
            registrations[id] = registration
        }
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        guard suspendCount == 0 else { return }
        for (id, var registration) in registrations {
            registration.ref = install(registration.combo, id: id)
            registrations[id] = registration
        }
    }

    private func install(_ combo: KeyCombo, id: UInt32) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != OSStatus(noErr) {
            NSLog("RegisterEventHotKey failed (\(status)) for \(combo.displayString)")
        }
        return ref
    }

    fileprivate func fire(_ id: UInt32) {
        registrations[id]?.handler()
    }
}
