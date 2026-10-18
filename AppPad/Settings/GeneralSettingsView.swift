import SwiftUI
import AppKit

// App-wide settings shared by every feature (not tied to one panel).
struct GeneralSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        guard newValue != LoginItem.isEnabled else { return }
                        LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }

            // Shared by AppPad, Clipboard, Workflows and the Settings sidebar.
            Section("Appearance") {
                // Tabs like the sidebar: glass lens on macOS 26, pill otherwise.
                LabeledContent {
                    GlassSegmentedControl(
                        segments: AppTheme.allCases.map {
                            GlassSegment(value: $0, title: $0.tabTitle, icon: $0.tabIcon,
                                         selectedIcon: $0.tabSelectedIcon)
                        },
                        selection:          prefs.appTheme,
                        metrics:            .themeTabs,
                        selectedLabelColor: .accentColor,
                        glass:              prefs.glassControls,
                        onSelect:           { prefs.appTheme = $0 }
                    )
                    .fixedSize()
                    .padding(.vertical, 6)   // room for the lifted lens
                } label: {
                    Text("Theme")
                    Text("Auto follows the macOS appearance. AppPad, Clipboard and Workflows backgrounds follow the theme.")
                }
                // Liquid Glass needs macOS 26; hidden on older systems.
                if GlassAvailability.isSupported {
                    Toggle(isOn: $prefs.glassControls) {
                        Text("Liquid Glass controls")
                        Text("Applies to search fields and controls in AppPad, Clipboard and Workflows.")
                    }
                }
            }

            Section("Keyboard") {
                Toggle(isOn: $prefs.escClearsSearchFirst) {
                    Text("Esc clears the search first")
                    Text("When on, Esc clears the search text first and closes on the next press. When off, Esc closes right away. Applies to AppPad, Clipboard and Workflows.")
                }
            }

            Section("Displays") {
                Toggle(isOn: $prefs.panelsFollowMouseScreen) {
                    Text("Open on the display with the pointer")
                    Text("Applies to AppPad, Clipboard and Workflows. When off, they open on the main display.")
                }
            }
        }
        .formStyle(.grouped)
        // Login item may be toggled from the menu bar while Settings stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            launchAtLogin = LoginItem.isEnabled
        }
    }
}

// Theme tab labels and symbols.
private extension AppTheme {
    var tabTitle: String {
        switch self {
        case .auto: return String(localized: "Auto")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var tabIcon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var tabSelectedIcon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

extension GlassSegmentMetrics {
    // Theme tabs in General: a bit larger than .regular to suit a form row.
    static var themeTabs: GlassSegmentMetrics {
        GlassSegmentMetrics(font: .system(size: 13, weight: .medium),
                            nsFont: .systemFont(ofSize: 13, weight: .medium),
                            segmentHeight: 28, labelHPadding: 14, inset: 2)
    }
}

// Background rows shared by the AppPad, Clipboard and Workflows settings.
// Every style keeps its own blur / transparency (and custom color) per light / dark theme.
// Stored as opacity; color styles show it as transparency (1 − opacity).
struct BackgroundSection: View {
    @Binding var settings: BackgroundSettings
    var allowsFollow: Bool
    // Theme whose values the sliders edit; starts at the theme in effect.
    @State private var variant: ThemeVariant = PanelBackgroundSpec.currentVariant
    // Glass flag for the theme tabs.
    @ObservedObject private var prefs = Preferences.shared

    private var isOwn: Bool { !allowsFollow || !settings.follow }

    var body: some View {
        Section {
            if allowsFollow {
                Toggle(isOn: $settings.follow) {
                    Text("Same as AppPad")
                    Text("Uses AppPad's background, blur and transparency.")
                }
            }
            if isOwn {
                Picker("Background", selection: $settings.style) {
                    Text("White").tag(BackgroundStyle.white)
                    Text("Light gray").tag(BackgroundStyle.lightGray)
                    Text("Dark gray").tag(BackgroundStyle.darkGray)
                    Text("Wallpaper").tag(BackgroundStyle.wallpaper)
                    Text("Custom color").tag(BackgroundStyle.custom)
                }
                // Same tabs as the General theme switch.
                LabeledContent("Adjust for") {
                    GlassSegmentedControl(
                        segments: [
                            GlassSegment(value: ThemeVariant.light, title: AppTheme.light.tabTitle,
                                         icon: AppTheme.light.tabIcon, selectedIcon: AppTheme.light.tabSelectedIcon),
                            GlassSegment(value: ThemeVariant.dark, title: AppTheme.dark.tabTitle,
                                         icon: AppTheme.dark.tabIcon, selectedIcon: AppTheme.dark.tabSelectedIcon),
                        ],
                        selection:          variant,
                        metrics:            .themeTabs,
                        selectedLabelColor: .accentColor,
                        glass:              prefs.glassControls,
                        onSelect:           { variant = $0 }
                    )
                    .fixedSize()
                    .padding(.vertical, 6)   // room for the lifted lens
                }
                if settings.style == .custom {
                    ColorPicker("Color", selection: customColor, supportsOpacity: false)
                }
                percentSlider("Blur", value: tuningBinding(\.blur))
                    .disabled(tuning.opacity >= 0.995)   // fully covered: blur is invisible
                if settings.style == .wallpaper {
                    percentSlider("Tint", value: tuningBinding(\.opacity))
                } else {
                    percentSlider("Transparency", value: transparencyBinding)
                }
                HStack {
                    Spacer()
                    Button("Restore Defaults") { settings.resetTuning(settings.style, variant) }
                }
            }
        } header: {
            Text("Background")
        } footer: {
            if isOwn {
                VStack(alignment: .leading, spacing: 2) {
                    if settings.style == .wallpaper {
                        Text("Blur and Tint apply to the desktop wallpaper.")
                    } else {
                        Text("Above \(Double(0).formatted(.percent)) transparency the open windows behind show through, blurred by the Blur value.")
                    }
                    Text("Each background keeps its own values for the light and dark theme.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var tuning: BackgroundTuning { settings.tuning(settings.style, variant) }

    private func tuningBinding(_ path: WritableKeyPath<BackgroundTuning, Double>) -> Binding<Double> {
        Binding(
            get: { tuning[keyPath: path] },
            set: { value in
                var t = tuning
                t[keyPath: path] = value
                settings.setTuning(t, settings.style, variant)
            }
        )
    }

    // Transparency = 1 − stored opacity.
    private var transparencyBinding: Binding<Double> {
        Binding(
            get: { 1 - tuning.opacity },
            set: { value in
                var t = tuning
                t.opacity = 1 - value
                settings.setTuning(t, settings.style, variant)
            }
        )
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: ClipboardColors.color(hex: settings.customHex(variant)) ?? .gray) },
            set: { settings.customColors[variant.rawValue] = ClipboardColors.hex(NSColor($0)) }
        )
    }

    private func percentSlider(_ title: LocalizedStringKey, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: 0...1, step: 0.05)
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: 220)
        }
    }
}
