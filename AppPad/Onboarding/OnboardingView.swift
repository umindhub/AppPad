import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox
import UniformTypeIdentifiers

enum OnboardingPage: Int, CaseIterable {
    case welcome, features, pinch, clipboard, spotlight, appShortcuts, ai, permissions, done
}

// Paged welcome guide hosted by OnboardingGuide's window.
struct OnboardingView: View {
    static let size = NSSize(width: 960, height: 600)   // 16:10

    @ObservedObject var prefs: Preferences
    var onFinish: () -> Void
    var onSkip: () -> Void

    @State private var page: OnboardingPage = .welcome
    @State private var forward = true
    // Bumped every second / on activation: system state may change in System Settings.
    @State private var tick = 0
    @State private var scrubbingDots = false
    @State private var hoveringDots = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(prefs: Preferences, onFinish: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.prefs = prefs
        self.onFinish = onFinish
        self.onSkip = onSkip
    }

    private var useGlass: Bool { GlassAvailability.isSupported && prefs.glassControls }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                pageContent
                    .id(page)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 56)
            .padding(.top, 36)
            .clipped()
            bottomBar
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(escapeButton)
        .onReceive(timer) { _ in tick &+= 1 }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingSwipe)) { note in
            if let delta = note.userInfo?["step"] as? Int { step(delta) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            tick &+= 1
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome: WelcomePage()
        case .features: FeaturesPage(prefs: prefs)
        case .pinch: PinchPage(prefs: prefs, glass: useGlass)
        case .clipboard: ClipboardPage(prefs: prefs)
        case .spotlight: SpotlightPage(prefs: prefs, glass: useGlass, tick: tick)
        case .appShortcuts: AppShortcutsPage(prefs: prefs, glass: useGlass)
        case .ai: AIPage(glass: useGlass)
        case .permissions: PermissionsPage(glass: useGlass, tick: tick)
        case .done: DonePage(prefs: prefs)
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    // MARK: Navigation

    private func go(to target: OnboardingPage) {
        guard target != page else { return }
        forward = target.rawValue > page.rawValue
        // Next run loop: the old page picks up the new direction for its removal.
        DispatchQueue.main.async {
            withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = target }
        }
    }

    private func step(_ delta: Int) {
        guard let target = OnboardingPage(rawValue: page.rawValue + delta) else { return }
        go(to: target)
    }

    private var primaryTitle: LocalizedStringKey {
        switch page {
        case .welcome: return "Get Started"
        case .done: return "Open AppPad"
        default: return "Continue"
        }
    }

    private var bottomBar: some View {
        ZStack {
            pageDots
            HStack(spacing: 10) {
                if page != .done {
                    Button("Skip", action: onSkip)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if page != .welcome {
                    Button("Back") { step(-1) }
                        .onboardingSecondary(glass: useGlass)
                }
                Button {
                    page == .done ? onFinish() : step(1)
                } label: {
                    Text(primaryTitle).frame(minWidth: 92)
                }
                .keyboardShortcut(.defaultAction)
                .onboardingProminent(glass: useGlass)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    // Tap anywhere on the dots to jump; press and drag to scrub through pages.
    private static let dotPitch: CGFloat = 16
    private static let dotInset: CGFloat = 8

    private var pageDots: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingPage.allCases, id: \.self) { item in
                Circle()
                    .fill(item == page ? Color.accentColor : Color.primary.opacity(0.2))
                    .frame(width: item == page ? 8 : 7, height: item == page ? 8 : 7)
                    .frame(width: Self.dotPitch, height: 24)
            }
        }
        .padding(.horizontal, Self.dotInset)
        .background(
            Capsule().fill(Color.primary.opacity(scrubbingDots ? 0.10 : (hoveringDots ? 0.05 : 0)))
        )
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    scrubbingDots = true
                    scrubDots(to: value.location.x)
                }
                .onEnded { value in
                    scrubDots(to: value.location.x)
                    scrubbingDots = false
                }
        )
        .onHover { hoveringDots = $0 }
        .animation(.easeOut(duration: 0.15), value: scrubbingDots)
        .animation(.easeOut(duration: 0.15), value: hoveringDots)
        .animation(.easeOut(duration: 0.2), value: page)
    }

    private func scrubDots(to x: CGFloat) {
        let count = OnboardingPage.allCases.count
        let index = Int(((x - Self.dotInset) / Self.dotPitch).rounded(.down))
        guard let target = OnboardingPage(rawValue: min(max(index, 0), count - 1)) else { return }
        go(to: target)
    }

    // Esc closes the guide on every page.
    private var escapeButton: some View {
        Button(action: onSkip) { EmptyView() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 10)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
            VStack(spacing: 10) {
                Text("Welcome to AppPad")
                    .font(.system(size: 30, weight: .bold))
                Text("Built for Mac: the fast, authentic Launchpad, just like in macOS 15.")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .multilineTextAlignment(.center)
                Text("Plus clipboard history, workflows, window control and app shortcuts — all from the menu bar.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 620)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Setup takes about a minute.")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FeaturesPage: View {
    @ObservedObject var prefs: Preferences
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)

    var body: some View {
        VStack(spacing: 22) {
            OnboardingTitle(
                title: String(localized: "What AppPad can do"),
                subtitle: String(localized: "Everything lives in the menu bar. You can change every shortcut in Settings.")
            )
            LazyVGrid(columns: Self.columns, spacing: 14) {
                FeatureCard(icon: .image(StatusBarController.makeIcon(padded: false)), tint: .blue,
                            title: String(localized: "AppPad"),
                            detail: String(localized: "All your apps in a Launchpad-style grid with folders, search and drag and drop."),
                            shortcut: prefs.pinchToOpen ? String(localized: "Four-finger pinch") : nil)
                FeatureCard(icon: .symbol("doc.on.clipboard"), tint: .orange,
                            title: String(localized: "Clipboard"),
                            detail: String(localized: "History of copied text, images and files, plus a library of saved clips."),
                            shortcut: prefs.clipboardEnabled ? prefs.clipboardHotKey?.displayString : nil)
                FeatureCard(icon: .symbol("bolt"), tint: .yellow,
                            title: String(localized: "Workflows"),
                            detail: String(localized: "Open apps and run actions like a timer or Empty Trash from one search field."),
                            shortcut: prefs.workflowPanelHotKey?.displayString)
                FeatureCard(icon: .symbol("rectangle.split.2x1"), tint: .green,
                            title: String(localized: "Windows"),
                            detail: String(localized: "Snap, maximize and move windows between displays with the keyboard."),
                            shortcut: nil)
                FeatureCard(icon: .symbol("keyboard"), tint: .purple,
                            title: String(localized: "App Shortcuts"),
                            detail: String(localized: "Give any app its own global shortcut to open or hide it."),
                            shortcut: nil)
                FeatureCard(icon: .symbol("sparkles"), tint: .pink,
                            title: String(localized: "AI Assistants (MCP)"),
                            detail: String(localized: "Let AI assistants run your workflows and even write new ones."),
                            shortcut: nil)
            }
        }
    }
}

private struct PinchPage: View {
    @ObservedObject var prefs: Preferences
    var glass: Bool

    var body: some View {
        SplitPage(
            symbol: "hand.pinch",
            title: String(localized: "Open AppPad with a pinch"),
            subtitle: String(localized: "Pinch with thumb and three fingers to open AppPad and spread them to close it, just like Launchpad.")
        ) {
            OnboardingCard {
                Toggle(isOn: $prefs.pinchToOpen) {
                    Text("Four-finger pinch opens AppPad").fontWeight(.medium)
                }
                .toggleStyle(.appSwitch)
                Divider()
                if prefs.pinchToOpen {
                    PinchSetupStepsView(showsButton: false)
                    HStack {
                        Spacer()
                        Button("Open Trackpad Settings") { PinchSetupGuide.openTrackpadSettings() }
                            .onboardingSecondary(glass: glass)
                    }
                } else {
                    Text("You can still open AppPad from the menu bar icon or the Dock.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct SpotlightPage: View {
    @ObservedObject var prefs: Preferences
    var glass: Bool
    var tick: Int
    @State private var result: SpotlightShortcut.ToggleResult?

    init(prefs: Preferences, glass: Bool, tick: Int) {
        self.prefs = prefs
        self.glass = glass
        self.tick = tick
    }

    var body: some View {
        let _ = tick   // re-evaluate live state on every tick
        let combo = prefs.workflowPanelHotKey
        let comboText = combo?.displayString ?? ""
        let conflict = SpotlightShortcut.conflicts(with: combo)

        SplitPage(
            symbol: "command",
            title: combo == nil ? String(localized: "Workflows")
                                : String(localized: "Use \(comboText) for Workflows"),
            subtitle: combo == nil
                ? String(localized: "Open apps and run actions like a timer or Empty Trash from one search field.")
                : String(localized: "macOS gives \(comboText) to Spotlight by default. Turn off Spotlight's shortcut to use it for AppPad Workflows instead.")
        ) {
            OnboardingCard {
                if combo == nil {
                    Label("Workflows has no global shortcut. You can set one in Settings › Workflows.",
                          systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                } else if conflict {
                    conflictContent
                } else {
                    readyContent(comboText)
                }
            }
        }
    }

    @ViewBuilder
    private var conflictContent: some View {
        Label("Spotlight still uses this shortcut, so it opens Spotlight instead of AppPad.",
              systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 10) {
            Button("Turn Off Spotlight Shortcut") {
                result = SpotlightShortcut.setSpotlightSearchEnabled(false)
            }
            .onboardingProminent(glass: glass)
            Button("Open Keyboard Settings") { SpotlightShortcut.openKeyboardShortcuts() }
                .onboardingSecondary(glass: glass)
        }
        if result == .failed {
            Text("System Settings › Keyboard › Keyboard Shortcuts › Spotlight: turn off “Show Spotlight search” or give it another shortcut.")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func readyContent(_ comboText: String) -> some View {
        Label {
            Text(verbatim: String(localized: "\(comboText) now opens Workflows."))
                .fontWeight(.medium)
        } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
        if result == .needsRelogin {
            Text(verbatim: String(localized: "If \(comboText) still opens Spotlight, log out and back in."))
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if SpotlightShortcut.isTurnedOff {
            Text("You can give Spotlight another shortcut in Keyboard Settings, or turn its shortcut back on here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                Button("Restore Spotlight Shortcut") {
                    result = SpotlightShortcut.setSpotlightSearchEnabled(true)
                    if result != .failed { result = nil }
                }
                .onboardingSecondary(glass: glass)
                Button("Open Keyboard Settings") { SpotlightShortcut.openKeyboardShortcuts() }
                    .onboardingSecondary(glass: glass)
            }
        }
    }
}

private struct ClipboardPage: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        SplitPage(
            symbol: "doc.on.clipboard",
            title: String(localized: "Everything you copy, one shortcut away"),
            subtitle: String(localized: "AppPad keeps the text, images and files you copy. Items you save stay until you remove them.")
        ) {
            OnboardingCard {
                Toggle(isOn: $prefs.clipboardEnabled) {
                    Text("Enable clipboard history").fontWeight(.medium)
                }
                .toggleStyle(.appSwitch)
                if prefs.clipboardEnabled {
                    Divider()
                    shortcutRow(String(localized: "Clipboard"), prefs.clipboardHotKey?.displayString)
                    shortcutRow(String(localized: "Saved items"), prefs.clipboardSavedHotKey?.displayString)
                }
            }
            if prefs.clipboardEnabled {
                OnboardingCard {
                    tipRow("⌘1–⌘0", String(localized: "Paste one of the first ten items"))
                    tipRow("⌘S", String(localized: "Save the selected item"))
                    tipRow("⌘↩", String(localized: "Name a saved item or edit its text"))
                    tipRow(String(localized: "Click the Safari icon to show only items copied from Safari")) {
                        AppFilterChip(icon: Self.safariIcon)
                    }
                }
            }
        }
    }

    private func shortcutRow(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            if let value { KeyChip(text: value) }
        }
    }

    // Safari's icon, or the generic app icon if it is missing.
    private static var safariIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    private func tipRow(_ keys: String, _ text: String) -> some View {
        tipRow(text) { KeyChip(text: keys) }
    }

    private func tipRow<Leading: View>(_ text: String, @ViewBuilder leading: () -> Leading) -> some View {
        HStack(spacing: 12) {
            leading()
                .frame(width: 76, alignment: .leading)
            Text(verbatim: text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct AppShortcutsPage: View {
    @ObservedObject var prefs: Preferences
    var glass: Bool

    private static let safariKey = "com.apple.Safari"
    // ⌃⌘J, the example shortcut for Safari.
    private static let example = KeyCombo(keyCode: UInt32(kVK_ANSI_J),
                                          modifiers: UInt32(cmdKey | controlKey),
                                          keyLabel: "J")

    init(prefs: Preferences, glass: Bool) {
        self.prefs = prefs
        self.glass = glass
    }

    private var safariURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.safariKey)
    }

    var body: some View {
        SplitPage(
            symbol: "keyboard",
            title: String(localized: "A shortcut for every app"),
            subtitle: String(localized: "Press it to open or switch to the app, and press it again to hide it. It works wherever you are.")
        ) {
            if let url = safariURL {
                OnboardingCard {
                    Text("Try it with Safari:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    safariRow(url)
                }
            }
            OnboardingCard {
                Text("Add more in Settings › App Shortcuts, or choose Set Shortcut… on an app in AppPad.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Open App Shortcuts") { OnboardingGuide.openSettings?(.shortcuts) }
                        .onboardingSecondary(glass: glass)
                }
            }
        }
    }

    @ViewBuilder
    private func safariRow(_ url: URL) -> some View {
        let combo = Self.example
        let comboText = combo.displayString
        let current = prefs.appHotKeys.first { $0.key == Self.safariKey }?.combo
        let conflict = prefs.conflictName(for: combo, excluding: .app(Self.safariKey))

        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Safari").fontWeight(.medium)
                if current == combo {
                    Label {
                        Text(verbatim: String(localized: "Press \(comboText) to try it."))
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.callout)
                } else if let current {
                    Text(verbatim: String(localized: "Safari already uses \(current.displayString)."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if let conflict {
                    Text(verbatim: String(localized: "\(comboText) is already used by \(conflict)."))
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            KeyChip(text: current?.displayString ?? comboText)
            if current == combo {
                Button("Remove") { setSafari(nil, url: url) }
                    .onboardingSecondary(glass: glass, size: .regular)
            } else if current == nil {
                Button(String(localized: "Set \(comboText) for Safari")) { setSafari(combo, url: url) }
                    .onboardingProminent(glass: glass, size: .regular)
                    .disabled(conflict != nil)
            }
        }
    }

    // Same storage as Settings › App Shortcuts; hotkeys re-register via preferencesDidChange.
    private func setSafari(_ combo: KeyCombo?, url: URL) {
        if let index = prefs.appHotKeys.firstIndex(where: { $0.key == Self.safariKey }) {
            if let combo {
                prefs.appHotKeys[index].combo = combo
            } else {
                prefs.appHotKeys.remove(at: index)
            }
        } else if let combo {
            let name = (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension
            prefs.appHotKeys.append(AppHotKey(key: Self.safariKey, path: url.path, name: name, combo: combo))
        }
    }
}

private struct AIPage: View {
    @ObservedObject private var host = MCPHost.shared
    @ObservedObject private var claude = ClaudeDesktopMCP.shared
    var glass: Bool
    @State private var client: Client = .other
    @State private var copied: String?
    @State private var claudeMessage: ClaudeMessage?

    private struct ClaudeMessage: Equatable {
        var text: String
        var failed: Bool
    }

    private enum Client { case claudeCode, other }

    init(glass: Bool) {
        self.glass = glass
    }

    private static let examples: [String] = [
        String(localized: "Write an AppPad workflow that shows the free space on my disk."),
        String(localized: "Write an AppPad workflow that starts my GitHub Actions deploy for a branch."),
        String(localized: "Tidy up my AppPad: keep the system apps in their current order, and put third-party apps into folders by category after them."),
    ]

    var body: some View {
        SplitPage(
            symbol: "sparkles",
            title: String(localized: "Let AI write workflows for you"),
            subtitle: String(localized: "Describe what you need in plain words: Claude or another MCP client writes the workflow for you, and can even tidy up your app icons into pages and folders.")
        ) {
            OnboardingCard {
                Toggle(isOn: $host.enabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow AI assistants to use workflows").fontWeight(.medium)
                        Text("Claude and other MCP clients can list, run and write your workflows. You approve every new or changed workflow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.appSwitch)
                if host.enabled {
                    Divider()
                    claudeDesktopRow
                    Picker(selection: $client) {
                        Text("Claude Desktop, Cursor and other clients").tag(Client.other)
                        Text(verbatim: "Claude Code").tag(Client.claudeCode)
                    } label: {
                        EmptyView()
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    snippet(client == .claudeCode ? MCPClientConfig.claudeCodeCommand : MCPClientConfig.json)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Group {
                            if client == .claudeCode {
                                Text("Run once in Terminal.")
                            } else {
                                Text("Add this to the client's MCP configuration (Claude Desktop: claude_desktop_config.json), then restart the client.")
                            }
                        }
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        statusText
                    }
                    .font(.caption)
                }
            }
            OnboardingCard {
                Text("Try asking your AI assistant:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(Self.examples, id: \.self) { example in
                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(Color.accentColor)
                        Text(verbatim: example)
                            .font(.callout)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        copyButton(example)
                    }
                }
            }
        }
    }

    // One-click Claude Desktop setup (same service as Settings and the built-in workflows).
    private var claudeDesktopRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Claude Desktop").fontWeight(.medium)
                // Always two caption lines tall: status ⇄ message never changes the row height.
                ZStack(alignment: .topLeading) {
                    Text(verbatim: "A\nA").hidden()
                    Group {
                        if let claudeMessage {
                            Text(verbatim: claudeMessage.text)
                                .foregroundStyle(claudeMessage.failed ? Color.red : Color.secondary)
                        } else {
                            ClaudeDesktopStatusText(status: claude.status)
                        }
                    }
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Add to Claude Desktop") { show(claude.add()) }
                .onboardingProminent(glass: glass, size: .small)
                .disabled(!claude.status.canAdd)
            Button("Remove from Claude Desktop") { show(claude.remove()) }
                .onboardingSecondary(glass: glass, size: .small)
                .disabled(!claude.status.canRemove)
        }
        .onAppear { claude.refresh() }
    }

    private func show(_ outcome: Result<String, ClaudeDesktopError>) {
        let message: ClaudeMessage
        switch outcome {
        case .success(let text): message = ClaudeMessage(text: text, failed: false)
        case .failure(let error): message = ClaudeMessage(text: error.message, failed: true)
        }
        claudeMessage = message
        Task {
            try? await Task.sleep(for: .seconds(8))
            if claudeMessage == message { claudeMessage = nil }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if !host.isListening {
            Text("Not running").foregroundStyle(.red)
        } else if host.clientCount == 0 {
            Text("Waiting for a client").foregroundStyle(.secondary)
        } else {
            Text("Connected clients: \(host.clientCount)").foregroundStyle(.green)
        }
    }

    // Monospaced setup text; long JSON scrolls inside a fixed height.
    private func snippet(_ text: String) -> some View {
        let code = Text(verbatim: text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        return HStack(alignment: .top, spacing: 8) {
            if text.split(separator: "\n").count > 5 {
                ScrollView(.vertical) { code }
                    .frame(height: 70)
            } else {
                code
            }
            copyButton(text)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    private func copyButton(_ text: String) -> some View {
        Button(copied == text ? LocalizedStringKey("Copied") : LocalizedStringKey("Copy")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = text
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if copied == text { copied = nil }
            }
        }
        .onboardingSecondary(glass: glass, size: .small)
    }
}

private struct PermissionsPage: View {
    var glass: Bool
    var tick: Int
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var askedForAccess = false

    init(glass: Bool, tick: Int) {
        self.glass = glass
        self.tick = tick
    }

    var body: some View {
        let trusted = tick >= 0 && PasteService.isTrusted   // tick: re-read every second

        SplitPage(
            symbol: "lock.shield",
            title: String(localized: "Permissions and startup"),
            subtitle: String(localized: "AppPad works without these, but some features need them. You can change them later in System Settings.")
        ) {
            OnboardingCard {
                OnboardingRow(symbol: "accessibility",
                              title: String(localized: "Accessibility"),
                              detail: String(localized: "Pastes clipboard items into the app you are using, and moves and resizes windows.")) {
                    if trusted {
                        Label("Allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") {
                            // First press: system prompt. Later presses: the Privacy pane.
                            if askedForAccess {
                                PasteService.openAccessibilitySettings()
                            } else {
                                askedForAccess = true
                                PasteService.requestAccess()
                            }
                        }
                        .onboardingSecondary(glass: glass)
                    }
                }
                Divider()
                OnboardingRow(symbol: "power",
                              title: String(localized: "Launch at login"),
                              detail: String(localized: "Keeps AppPad, the clipboard history and your shortcuts ready after you log in.")) {
                    Toggle(isOn: $launchAtLogin) { EmptyView() }
                        .toggleStyle(.appSwitch)
                        .labelsHidden()
                }
            }
        }
        .onChange(of: launchAtLogin) { _, newValue in
            guard newValue != LoginItem.isEnabled else { return }
            LoginItem.setEnabled(newValue)
            launchAtLogin = LoginItem.isEnabled
        }
        // May be toggled from the menu bar meanwhile.
        .onChange(of: tick) { _, _ in
            if launchAtLogin != LoginItem.isEnabled { launchAtLogin = LoginItem.isEnabled }
        }
    }
}

private struct DonePage: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        SplitPage(
            symbol: "checkmark",
            title: String(localized: "You're all set"),
            subtitle: String(localized: "Here is how to open everything. The menu bar icon has it all, too.")
        ) {
            OnboardingCard {
                referenceRow(String(localized: "AppPad"),
                             prefs.pinchToOpen ? String(localized: "Four-finger pinch") : String(localized: "Menu bar icon"))
                if prefs.clipboardEnabled {
                    Divider()
                    referenceRow(String(localized: "Clipboard"), prefs.clipboardHotKey?.displayString)
                    Divider()
                    referenceRow(String(localized: "Saved items"), prefs.clipboardSavedHotKey?.displayString)
                }
                Divider()
                referenceRow(String(localized: "Workflows"), prefs.workflowPanelHotKey?.displayString)
                Divider()
                referenceRow(String(localized: "Switch between panels"), "⌘⇧J / ⌘⇧K")
            }
        }
    }

    @ViewBuilder
    private func referenceRow(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(verbatim: title)
            Spacer()
            if let value { KeyChip(text: value) }
        }
    }
}

// MARK: - Building blocks

// Landscape page: title block on the left, content cards on the right.
private struct SplitPage<Content: View>: View {
    var symbol: String
    var title: String
    var subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 48) {
            OnboardingTitle(symbol: symbol, title: title, subtitle: subtitle, leading: true)
                .frame(width: 300)
            VStack(spacing: 14) {
                content
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct OnboardingTitle: View {
    var symbol: String? = nil
    var title: String
    var subtitle: String
    var leading = false

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: 10) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                                 startPoint: .top, endPoint: .bottom))
                    )
                    .padding(.bottom, 4)
            }
            Text(verbatim: title)
                .font(.system(size: 26, weight: .bold))
                .multilineTextAlignment(leading ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(leading ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: leading ? .infinity : 620, alignment: leading ? .leading : .center)
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .center)
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

private struct OnboardingRow<Trailing: View>: View {
    var symbol: String
    var title: String
    var detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).fontWeight(.medium)
                Text(verbatim: detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

private struct FeatureCard: View {
    enum Icon {
        case symbol(String)
        case image(NSImage)
    }

    var icon: Icon
    var tint: Color
    var title: String
    var detail: String
    var shortcut: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            iconView
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let shortcut { KeyChip(text: shortcut) }
                }
                Text(verbatim: detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(tint)
        case .image(let image):
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .foregroundStyle(tint)
        }
    }
}

// Looks like an app filter chip in the Clipboard panel.
private struct AppFilterChip: View {
    var icon: NSImage

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 18)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.5)))
    }
}

private struct KeyChip: View {
    var text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

// Pill buttons: Liquid Glass on macOS 26 with glass controls on, bordered capsule otherwise.
private extension View {
    func onboardingProminent(glass: Bool, size: SwiftUI.ControlSize = .large) -> some View {
        prominentStyle(glass: glass, size: size).buttonBorderShape(.capsule)
    }

    func onboardingSecondary(glass: Bool, size: SwiftUI.ControlSize = .large) -> some View {
        secondaryStyle(glass: glass, size: size).buttonBorderShape(.capsule)
    }

    @ViewBuilder
    private func prominentStyle(glass: Bool, size: SwiftUI.ControlSize) -> some View {
        if glass {
            if #available(macOS 26.0, *) {
                self.buttonStyle(.glassProminent).controlSize(size)
            } else {
                self.buttonStyle(.borderedProminent).controlSize(size)
            }
        } else {
            self.buttonStyle(.borderedProminent).controlSize(size)
        }
    }

    @ViewBuilder
    private func secondaryStyle(glass: Bool, size: SwiftUI.ControlSize) -> some View {
        if glass {
            if #available(macOS 26.0, *) {
                self.buttonStyle(.glass).controlSize(size)
            } else {
                self.buttonStyle(.bordered).controlSize(size)
            }
        } else {
            self.buttonStyle(.bordered).controlSize(size)
        }
    }
}
