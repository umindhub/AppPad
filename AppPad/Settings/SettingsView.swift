import SwiftUI
import AppKit

// Case order = sidebar order.
enum SettingsTab: String, CaseIterable {
    case general, launchpad, clipboard, workflows, shortcuts, windows

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

            Section("Window") {
                Picker("Background", selection: $prefs.backgroundStyle) {
                    Text("Blurred wallpaper").tag(PanelBackgroundStyle.wallpaper)
                    Text("White").tag(PanelBackgroundStyle.white)
                }
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
