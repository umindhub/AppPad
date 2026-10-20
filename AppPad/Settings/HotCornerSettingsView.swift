import SwiftUI
import AppKit

// Settings › AppPad › Hot Corners: one menu per screen corner around a small screen preview.
// Like macOS: choosing an action with ⌘ / ⌥ / ⌃ / ⇧ held (or a combination) makes that corner
// fire only while those keys are held.
struct HotCornerSection: View {
    @ObservedObject var prefs: Preferences
    // Corners also used by macOS hot corners; refreshed when Settings becomes key.
    @State private var systemCorners = SystemHotCorners.occupied()
    @State private var axTrusted = PasteService.isTrusted

    private static let menuWidth: CGFloat = 180
    private static let previewSize = CGSize(width: 160, height: 100)

    var body: some View {
        Section {
            HStack(spacing: 14) {
                VStack(alignment: .leading) {
                    menu(.topLeft)
                    Spacer(minLength: 0)
                    menu(.bottomLeft)
                }
                HotCornerPreview(config: prefs.hotCorners)
                    .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                VStack(alignment: .trailing) {
                    menu(.topRight)
                    Spacer(minLength: 0)
                    menu(.bottomRight)
                }
            }
            .frame(height: Self.previewSize.height)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)

            if !conflicts.isEmpty {
                LabeledContent {
                    Button("Open System Settings") { SystemHotCorners.openSettings() }
                } label: {
                    warning(conflictMessage)
                }
            }

            if !axTrusted && prefs.hotCorners.uses(\.needsAccessibility) {
                LabeledContent {
                    Button("Grant Access…") {
                        PasteService.requestAccess()
                        PasteService.openAccessibilitySettings()
                    }
                } label: {
                    warning(String(localized: "Notification Center and Quick Note need Accessibility permission."))
                }
            }
        } header: {
            Text("Hot Corners")
        } footer: {
            Text("Move the pointer into a corner of the screen to run its action. Hold ⌘, ⌥, ⌃ or ⇧ (or several) while choosing an action to make the corner work only while those keys are held.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            systemCorners = SystemHotCorners.occupied()
            axTrusted = PasteService.isTrusted
        }
    }

    private func menu(_ corner: HotCorner) -> some View {
        HotCornerPopUp(
            corner: corner,
            setting: prefs.hotCorners[corner],
            clipboardEnabled: prefs.clipboardEnabled,
            onChange: { prefs.hotCorners[corner] = $0 }
        )
        .frame(width: Self.menuWidth)
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }

    private var conflicts: [HotCorner] {
        HotCorner.allCases.filter { prefs.hotCorners[$0].isSet && systemCorners.contains($0) }
    }

    private var conflictMessage: String {
        let list = ListFormatter.localizedString(byJoining: conflicts.map(\.title))
        return String(localized: "macOS hot corners also use: \(list). Both run when the pointer reaches that corner.")
    }
}

// Desktop sketch with a menu bar; set corners get a dot.
private struct HotCornerPreview: View {
    let config: HotCornerConfig

    private static let radius: CGFloat = 7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(LinearGradient(
                colors: [Color.accentColor.opacity(0.65), Color.accentColor.opacity(0.25)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle()
                .fill(Color.white.opacity(0.45))
                .frame(height: 8)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.secondary.opacity(0.35)))
        .overlay(alignment: .topLeading) { marker(.topLeft) }
        .overlay(alignment: .topTrailing) { marker(.topRight) }
        .overlay(alignment: .bottomLeading) { marker(.bottomLeft) }
        .overlay(alignment: .bottomTrailing) { marker(.bottomRight) }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func marker(_ corner: HotCorner) -> some View {
        if config[corner].isSet {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.25), radius: 1)
                .frame(width: 9, height: 9)
                .padding(5)
        }
    }
}

// NSPopUpButton: every modifier combination is an alternate item, so holding keys while the
// menu is open shows "⌃⌘ Action" entries, the same way the macOS hot corner menus do.
// Groups: AppPad features | macOS actions | none, split by separators.
private struct HotCornerPopUp: NSViewRepresentable {
    let corner: HotCorner
    let setting: HotCornerSetting
    let clipboardEnabled: Bool
    let onChange: (HotCornerSetting) -> Void

    // Tag = action index * 16 + modifiers raw value; none = -1.
    private static let allActions = HotCornerAction.allCases
    private static let noneTag = -1

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.autoenablesItems = false
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.setAccessibilityLabel(corner.title)
        button.toolTip = corner.title
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rebuild(button)
        context.coordinator.builtClipboardEnabled = clipboardEnabled
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // Menu holds ~190 items: rebuild only when an item's enabled state changes.
        if coordinator.builtClipboardEnabled != clipboardEnabled {
            coordinator.builtClipboardEnabled = clipboardEnabled
            rebuild(button)
        } else {
            button.selectItem(withTag: Self.tag(for: setting))
        }
    }

    private func rebuild(_ button: NSPopUpButton) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addGroup(HotCornerAction.appPadActions, to: menu)
        menu.addItem(.separator())
        addGroup(HotCornerAction.systemActions, to: menu)
        menu.addItem(.separator())
        let none = NSMenuItem(title: HotCornerAction.none.title, action: nil, keyEquivalent: "")
        none.keyEquivalentModifierMask = []
        none.tag = Self.noneTag
        menu.addItem(none)
        button.menu = menu
        button.selectItem(withTag: Self.tag(for: setting))
    }

    // Plain item followed by its alternates (same empty key equivalent, different modifiers).
    private func addGroup(_ actions: [HotCornerAction], to menu: NSMenu) {
        for action in actions {
            let enabled = action != .clipboard || clipboardEnabled || setting.action == .clipboard
            let plain = NSMenuItem(title: action.title, action: nil, keyEquivalent: "")
            plain.keyEquivalentModifierMask = []
            plain.tag = Self.tag(for: HotCornerSetting(action: action))
            plain.isEnabled = enabled
            menu.addItem(plain)
            for modifiers in HotCornerModifiers.combinations {
                let variant = HotCornerSetting(action: action, modifiers: modifiers)
                let item = NSMenuItem(title: variant.title, action: nil, keyEquivalent: "")
                item.keyEquivalentModifierMask = modifiers.eventFlags
                item.isAlternate = true
                item.tag = Self.tag(for: variant)
                item.isEnabled = enabled
                menu.addItem(item)
            }
        }
    }

    fileprivate static func tag(for setting: HotCornerSetting) -> Int {
        guard setting.isSet, let index = allActions.firstIndex(of: setting.action) else { return noneTag }
        return index * 16 + setting.modifiers.rawValue
    }

    fileprivate static func setting(forTag tag: Int) -> HotCornerSetting {
        guard tag >= 0, tag / 16 < allActions.count else { return HotCornerSetting() }
        return HotCornerSetting(action: allActions[tag / 16], modifiers: HotCornerModifiers(rawValue: tag % 16))
    }

    final class Coordinator: NSObject {
        var parent: HotCornerPopUp
        var builtClipboardEnabled: Bool?

        init(_ parent: HotCornerPopUp) { self.parent = parent }

        @objc func picked(_ sender: NSPopUpButton) {
            guard let item = sender.selectedItem else { return }
            var setting = HotCornerPopUp.setting(forTag: item.tag)
            // Keys still held at the click count too (alternate not swapped in).
            if setting.isSet, let flags = NSApp.currentEvent?.modifierFlags {
                setting.modifiers.formUnion(HotCornerModifiers(flags))
            }
            parent.onChange(setting)
        }
    }
}
