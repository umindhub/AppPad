import SwiftUI
import AppKit

enum SettingsTab: String, CaseIterable {
    case launchpad, clipboard, shortcuts, windows, workflows

    // UserDefaults key shared with @AppStorage (also set from AppDelegate).
    static let storageKey = "settingsTab"

    var title: String {
        switch self {
        case .launchpad: return String(localized: "AppPad")
        case .clipboard: return String(localized: "Clipboard")
        case .shortcuts: return String(localized: "App Shortcuts")
        case .windows: return String(localized: "Windows")
        case .workflows: return String(localized: "Workflows")
        }
    }

    var icon: String {
        switch self {
        case .launchpad: return "square.grid.3x3"
        case .clipboard: return "doc.on.clipboard"
        case .shortcuts: return "keyboard"
        case .windows: return "rectangle.split.2x1"
        case .workflows: return "bolt"
        }
    }

    // Launchpad tab uses the menu bar glyph instead of an SF Symbol.
    // Cached: segment items compare images by identity.
    @MainActor private static let appPadGlyph = StatusBarController.makeIcon(padded: false)

    @MainActor var iconImage: NSImage? {
        self == .launchpad ? Self.appPadGlyph : nil
    }

    var selectedIcon: String {
        switch self {
        case .launchpad: return "square.grid.3x3.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shortcuts: return "keyboard.fill"
        case .windows: return "rectangle.split.2x1.fill"
        case .workflows: return "bolt.fill"
        }
    }
}

extension GlassSegmentMetrics {
    // Settings sidebar: sized like a system sidebar List (larger text, bigger icons, taller rows).
    static var settingsSidebar: GlassSegmentMetrics {
        GlassSegmentMetrics(font: .system(size: 14, weight: .medium),
                            nsFont: .systemFont(ofSize: 14, weight: .medium),
                            segmentHeight: 34, labelHPadding: 12, inset: 2,
                            iconSpacing: 10, iconColumnWidth: 24, iconPointSize: 17)
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    var onResetLayout: () -> Void
    var clipboard: ClipboardMaintenance
    @State private var launchAtLogin = LoginItem.isEnabled
    @AppStorage(SettingsTab.storageKey) private var tabRaw = SettingsTab.launchpad.rawValue

    private var tab: SettingsTab { SettingsTab(rawValue: tabRaw) ?? .launchpad }

    // Outer padding left / right of the glass tab list.
    private static let sidebarHPadding: CGFloat = 10

    // Column width minus the width the sidebar content really gets
    // (floating glass sidebar margins on macOS 26); measured at runtime.
    @State private var sidebarChrome: CGFloat = 0

    // Sidebar width = widest row (icon box + gap + title) + row padding + outer padding * 2,
    // so the selected pill covers the whole label. Measured like GlassSegmentedNSView
    // renders labels; title at the lens weight (one step heavier) to stay safe.
    private var sidebarWidth: CGFloat {
        let m = GlassSegmentMetrics.settingsSidebar
        let titleFont = NSFont.systemFont(ofSize: m.nsFont.pointSize, weight: .semibold)
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: m.iconPointSize ?? m.nsFont.pointSize,
                                                       weight: .medium)
        let widest = SettingsTab.allCases.map { item -> CGFloat in
            let title = (item.title as NSString).size(withAttributes: [.font: titleFont]).width
            let icon = item.iconImage != nil
                ? (m.iconPointSize ?? m.nsFont.pointSize)
                : [item.icon, item.selectedIcon].compactMap {
                    NSImage(systemSymbolName: $0, accessibilityDescription: nil)?
                        .withSymbolConfiguration(symbolConfig)?.size.width
                }.max() ?? 0
            return max(icon, m.iconColumnWidth ?? 0) + m.iconSpacing + title
        }.max() ?? 0
        return ceil(widest + m.labelHPadding * 2 + m.inset * 2 + Self.sidebarHPadding * 2)
    }

    // Split view: Liquid Glass vertical tabs in the sidebar, selected page on the right.
    // Same control as YouMindHub's Settings sidebar (GlassSegmentedControl, axis .vertical);
    // pill layout when "Liquid Glass controls" is off.
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                GlassSegmentedControl(
                    segments: SettingsTab.allCases.map {
                        GlassSegment(value: $0, title: $0.title, icon: $0.icon,
                                     selectedIcon: $0.selectedIcon, iconImage: $0.iconImage)
                    },
                    selection:          tab,
                    metrics:            .settingsSidebar,
                    fillsWidth:         true,
                    selectedLabelColor: .accentColor,
                    axis:               .vertical,
                    glass:              prefs.glassControls,
                    onSelect:           { tabRaw = $0.rawValue }
                )
                // Room for the lifted lens (grows along the list, slightly across).
                .padding(.horizontal, Self.sidebarHPadding)
                .padding(.top, 10)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            // Content width < column width → add the difference back, so the
            // tab list itself is exactly `sidebarWidth` wide.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                let chrome = max(0, sidebarWidth + sidebarChrome - width)
                if abs(chrome - sidebarChrome) > 0.5 { sidebarChrome = chrome }
            }
            .navigationSplitViewColumnWidth(sidebarWidth + sidebarChrome)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(tab.title)
        }
        .frame(minWidth: 800, minHeight: 560)
        // Login item may be toggled from the menu bar while Settings stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = LoginItem.isEnabled
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .launchpad:
            launchpadForm
        case .clipboard:
            ClipboardSettingsView(prefs: prefs, maintenance: clipboard)
        case .shortcuts:
            AppShortcutsSettingsView(prefs: prefs)
        case .windows:
            WindowControlSettingsView(prefs: prefs)
        case .workflows:
            WorkflowSettingsView(prefs: prefs)
        }
    }

    private var launchpadForm: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        guard newValue != LoginItem.isEnabled else { return }
                        LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
                Toggle(isOn: $prefs.pinchToOpen) {
                    Text("Four-finger pinch opens AppPad")
                    Text("Pinch in to open, spread to close.")
                }
                if prefs.pinchToOpen {
                    PinchSetupStepsView(showsButton: true)
                }
                Picker("When opened", selection: $prefs.openPagePolicy) {
                    Text("Always first page").tag(OpenPagePolicy.firstPage)
                    Text("Last visited page").tag(OpenPagePolicy.lastPage)
                }
                Picker("Click on empty space", selection: $prefs.backgroundClickAction) {
                    Text("Close AppPad").tag(BackgroundClickAction.closePanel)
                    Text("Do nothing").tag(BackgroundClickAction.nothing)
                }
                Toggle("Switch to English input when opened", isOn: $prefs.switchToEnglishInput)
            }

            Section("Window") {
                Picker("Background", selection: $prefs.backgroundStyle) {
                    Text("Blurred wallpaper").tag(PanelBackgroundStyle.wallpaper)
                    Text("White").tag(PanelBackgroundStyle.white)
                }
                Toggle("Liquid Glass controls (search, page indicator)", isOn: $prefs.glassControls)
                Picker("Size", selection: $prefs.windowSizeMode) {
                    Text("Follow screen size").tag(WindowSizeMode.screenPercent)
                    Text("Custom").tag(WindowSizeMode.custom)
                }
                if prefs.windowSizeMode == .screenPercent {
                    LabeledContent("Screen percentage") {
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { Double(prefs.windowPercent) },
                                    set: { prefs.windowPercent = Int($0.rounded()) }
                                ),
                                in: 40...100,
                                step: 5
                            )
                            Text(Double(prefs.windowPercent) / 100, format: .percent)
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                        .frame(width: 220)
                    }
                } else {
                    Stepper("Width: \(prefs.customWidth) pt", value: $prefs.customWidth, in: 480...4000, step: 20)
                    Stepper("Height: \(prefs.customHeight) pt", value: $prefs.customHeight, in: 360...3000, step: 20)
                }
            }

            Section("Grid") {
                Stepper("Columns: \(prefs.gridColumns)", value: $prefs.gridColumns, in: 3...10)
                Stepper("Rows: \(prefs.gridRows)", value: $prefs.gridRows, in: 2...8)
                Picker("Page indicator", selection: $prefs.pageIndicatorStyle) {
                    Text("Dots").tag(PageIndicatorStyle.dots)
                    Text("Numbers").tag(PageIndicatorStyle.numbers)
                }
            }

            Section {
                Button("Reset Layout…", action: onResetLayout)
            }
        }
        .formStyle(.grouped)
    }
}
