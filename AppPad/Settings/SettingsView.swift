import SwiftUI
import AppKit

// Case order = sidebar order.
enum SettingsTab: String, CaseIterable {
    case general, launchpad, clipboard, workflows, shortcuts, windows, backup, about

    // UserDefaults key shared with @AppStorage (also set from AppDelegate).
    static let storageKey = "settingsTab"

    var title: String {
        switch self {
        case .general: return String(localized: "General")
        case .launchpad: return String(localized: "AppPad")
        case .clipboard: return String(localized: "Clipboard")
        case .shortcuts: return String(localized: "App Shortcuts")
        case .windows: return String(localized: "Windows")
        case .workflows: return String(localized: "Workflows")
        case .backup: return String(localized: "Backup")
        case .about: return String(localized: "About")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .launchpad: return "square.grid.3x3"
        case .clipboard: return "doc.on.clipboard"
        case .shortcuts: return "keyboard"
        case .windows: return "rectangle.split.2x1"
        case .workflows: return "bolt"
        case .backup: return "archivebox"
        case .about: return "info.circle"
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
        case .general: return "gearshape.fill"
        case .launchpad: return "square.grid.3x3.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .shortcuts: return "keyboard.fill"
        case .windows: return "rectangle.split.2x1.fill"
        case .workflows: return "bolt.fill"
        case .backup: return "archivebox.fill"
        // Outline on purpose: the sidebar draws symbols with one palette color, so the
        // knocked-out "i" of info.circle.fill would vanish (solid blue disc).
        case .about: return "info.circle"
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
    @AppStorage(SettingsTab.storageKey) private var tabRaw = SettingsTab.general.rawValue

    private var tab: SettingsTab { SettingsTab(rawValue: tabRaw) ?? .general }

    // Outer padding left / right of the glass tab list.
    private static let sidebarHPadding: CGFloat = 10

    // Fixed sidebar column width (no runtime measuring).
    private static let sidebarWidth: CGFloat = 300

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
            .navigationSplitViewColumnWidth(Self.sidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(tab.title)
        }
        .frame(minWidth: 800, minHeight: 560)
    }

    @ViewBuilder
    private var detail: some View {
        switch tab {
        case .general:
            GeneralSettingsView(prefs: prefs)
        case .launchpad:
            launchpadForm
        case .clipboard:
            ClipboardSettingsView(prefs: prefs, maintenance: clipboard)
        case .workflows:
            WorkflowSettingsView(prefs: prefs)
        case .shortcuts:
            AppShortcutsSettingsView(prefs: prefs)
        case .windows:
            WindowControlSettingsView(prefs: prefs)
        case .backup:
            BackupSettingsView()
        case .about:
            AboutSettingsView()
        }
    }

    private var launchpadForm: some View {
        Form {
            Section("Behavior") {
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

            // Always follows the screen size.
            Section("Window") {
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
                if prefs.windowPercent >= 100 {
                    Toggle(isOn: $prefs.launchpadCoversMenuBar) {
                        Text("Cover the menu bar")
                        Text("Fills the screen up to the top edge. The Dock stays below AppPad while it is open.")
                    }
                }
            }

            BackgroundSection(settings: $prefs.launchpadBackground, allowsFollow: false)

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
