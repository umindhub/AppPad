import Foundation
import Combine

nonisolated enum OpenPagePolicy: String, CaseIterable, Sendable {
    case firstPage, lastPage
}

nonisolated enum PageIndicatorStyle: String, CaseIterable, Sendable {
    case dots, numbers
}

nonisolated enum BackgroundClickAction: String, CaseIterable, Sendable {
    case closePanel   // like clicking outside (macOS 15 Launchpad)
    case nothing
}

// App-wide theme; .auto follows the system appearance.
nonisolated enum AppTheme: String, CaseIterable, Sendable {
    case auto, light, dark
}

// Effective light / dark side of the theme; every background option is tuned per variant.
nonisolated enum ThemeVariant: String, CaseIterable, Codable, Sendable {
    case light, dark
}

// Panels that draw a background.
nonisolated enum BackgroundSurface: Sendable {
    case launchpad, clipboard, workflows
}

// Base of a panel background. Wallpaper: blurred wallpaper + black veil.
// Colors: drawn at `opacity` over the live windows behind the panel.
nonisolated enum BackgroundStyle: String, CaseIterable, Codable, Sendable {
    case white, lightGray, darkGray, wallpaper, custom   // display order
}

// The two user-visible parameters (0…1).
// blur: wallpaper blur (wallpaper style) or blur of the windows behind (color styles).
// opacity: color layer on top (wallpaper style: a black veil; lighter default in the light theme).
nonisolated struct BackgroundTuning: Codable, Equatable, Sendable {
    var blur: Double
    var opacity: Double
}

// One panel's background settings. Every style keeps its own tuning (and custom color)
// per theme variant, so switching style or theme never needs re-adjusting.
// Missing entries fall back to BackgroundPalette defaults.
nonisolated struct BackgroundSettings: Codable, Equatable, Sendable {
    var follow: Bool                          // Clipboard / Workflows: use AppPad's background (ignored for AppPad)
    var style: BackgroundStyle
    var tunings: [String: BackgroundTuning]   // "style.variant"
    var customColors: [String: String]        // variant -> "#RRGGBB"

    static let launchpadDefault = BackgroundSettings(follow: false, style: .white, tunings: [:], customColors: [:])
    static let panelDefault = BackgroundSettings(follow: true, style: .white, tunings: [:], customColors: [:])

    private static func key(_ style: BackgroundStyle, _ variant: ThemeVariant) -> String {
        "\(style.rawValue).\(variant.rawValue)"
    }

    func tuning(_ style: BackgroundStyle, _ variant: ThemeVariant) -> BackgroundTuning {
        tunings[Self.key(style, variant)] ?? BackgroundPalette.defaultTuning(style, variant)
    }

    mutating func setTuning(_ tuning: BackgroundTuning, _ style: BackgroundStyle, _ variant: ThemeVariant) {
        tunings[Self.key(style, variant)] = tuning
    }

    mutating func resetTuning(_ style: BackgroundStyle, _ variant: ThemeVariant) {
        tunings[Self.key(style, variant)] = nil
    }

    func customHex(_ variant: ThemeVariant) -> String {
        customColors[variant.rawValue] ?? BackgroundPalette.defaultCustomHex(variant)
    }

    // Color drawn on top: preset / custom color; nil = wallpaper style (black veil).
    func colorHex(_ style: BackgroundStyle, _ variant: ThemeVariant) -> String? {
        style == .custom ? customHex(variant) : BackgroundPalette.presetHex(style, variant)
    }
}

// Built-in colors and defaults. Dark variants keep the light → dark order of the presets
// without being bright in the dark theme.
nonisolated enum BackgroundPalette {
    static func presetHex(_ style: BackgroundStyle, _ variant: ThemeVariant) -> String? {
        switch (style, variant) {
        case (.white, .light): return "#FFFFFF"
        case (.white, .dark): return "#48484A"
        case (.lightGray, .light): return "#E8E8ED"
        case (.lightGray, .dark): return "#3A3A3C"
        case (.darkGray, .light): return "#2C2C2E"
        case (.darkGray, .dark): return "#1C1C1E"
        case (.wallpaper, _), (.custom, _): return nil
        }
    }

    static func defaultCustomHex(_ variant: ThemeVariant) -> String {
        variant == .light ? "#DCE3EC" : "#3A3A3C"
    }

    static func defaultTuning(_ style: BackgroundStyle, _ variant: ThemeVariant) -> BackgroundTuning {
        switch style {
        case .wallpaper:
            // Same dark veil in both themes; light just a little brighter than dark.
            return BackgroundTuning(blur: 0.6, opacity: variant == .light ? 0.2 : 0.25)
        case .white, .lightGray, .darkGray, .custom:
            return BackgroundTuning(blur: 0.6, opacity: 0.5)   // 50% transparency over the windows behind
        }
    }

    // Internal third parameter: saturation boost of the blurred wallpaper (vibrancy, not user-facing).
    // Color styles use the system behind-window blur, which brings its own.
    static func saturation(_ style: BackgroundStyle) -> Double {
        style == .wallpaper ? 1.35 : 1.2
    }
}

extension Notification.Name {
    static let preferencesDidChange = Notification.Name("AppPad.preferencesDidChange")
}

// UserDefaults-backed settings; every change posts .preferencesDidChange.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let openPage = "openPagePolicy"
        static let indicator = "pageIndicatorStyle"
        static let columns = "gridColumns"
        static let rows = "gridRows"
        static let percent = "windowPercent"
        static let coverMenuBar = "launchpadCoversMenuBar"
        // Removed "Custom" size mode, cleared once on launch.
        static let legacySizeKeys = ["windowSizeMode", "customWidth", "customHeight"]
        static let theme = "appTheme"
        static let launchpadBackground = "launchpadBackground.v2"
        static let clipBackgroundV2 = "clipboardBackground.v2"
        static let workflowBackground = "workflowBackground.v2"
        static let workflowFollowsClipSize = "workflowFollowsClipboardSize"
        static let workflowWidth = "workflowWidthPercent"
        static let workflowHeight = "workflowHeightPercent"
        // Pre-v2 keys, read once for migration.
        static let legacyBackground = "backgroundStyle"
        static let backgroundClick = "backgroundClickAction"
        static let englishInput = "switchToEnglishInput"
        static let clipEnglishInput = "clipboardSwitchToEnglishInput"
        static let workflowEnglishInput = "workflowPanelSwitchToEnglishInput"
        static let halfLife = "frecencyHalfLifeDays"
        static let workflowHotKey = "workflowPanelHotKey"
        static let appHotKeys = "appHotKeys"
        static let glassControls = "glassControls"
        static let pinchToOpen = "pinchToOpen"
        static let followMouseScreen = "panelsFollowMouseScreen"
        static let escClearsFirst = "escClearsSearchFirst"
        static let clipEnabled = "clipboardEnabled"
        static let clipHotKey = "clipboardHotKey"
        static let clipSavedHotKey = "clipboardSavedHotKey"
        static let clipWidth = "clipboardWidthPercent"
        static let clipHeight = "clipboardHeightPercent"
        static let clipSearchFamily = "clipboardSearchFontFamily"
        static let clipSearchSize = "clipboardSearchFontSize"
        static let clipListFamily = "clipboardListFontFamily"
        static let clipListSize = "clipboardListFontSize"
        static let clipLimit = "clipboardHistoryLimit"
        static let clipDays = "clipboardRetentionDays"
        static let clipQuality = "clipboardImageQuality"
        static let clipAutoPaste = "clipboardAutoPaste"
        static let clipIgnored = "clipboardIgnoredApps"
        static let legacyClipBackground = "clipboardBackground"
        static let legacyClipBackgroundColor = "clipboardBackgroundColor"
        static let winEnabled = "windowControlEnabled"
        static let winHotKeyPrefix = "windowHotKey."
    }

    @Published var openPagePolicy: OpenPagePolicy { didSet { save(openPagePolicy.rawValue, Key.openPage) } }
    @Published var pageIndicatorStyle: PageIndicatorStyle { didSet { save(pageIndicatorStyle.rawValue, Key.indicator) } }
    @Published var gridColumns: Int { didSet { save(gridColumns, Key.columns) } }
    @Published var gridRows: Int { didSet { save(gridRows, Key.rows) } }
    // AppPad always follows the screen size (percent of the visible frame).
    @Published var windowPercent: Int { didSet { updatePanelMatch(); save(windowPercent, Key.percent) } }
    // At 100%: panel also covers the menu bar.
    @Published var launchpadCoversMenuBar: Bool { didSet { save(launchpadCoversMenuBar, Key.coverMenuBar) } }
    @Published var appTheme: AppTheme { didSet { save(appTheme.rawValue, Key.theme) } }
    @Published var launchpadBackground: BackgroundSettings { didSet { saveBackground(launchpadBackground, Key.launchpadBackground) } }
    @Published var backgroundClickAction: BackgroundClickAction { didSet { save(backgroundClickAction.rawValue, Key.backgroundClick) } }
    // Switch to an English (ASCII) input source while a panel is open; off by default for each panel.
    @Published var switchToEnglishInput: Bool { didSet { save(switchToEnglishInput, Key.englishInput) } }   // Launchpad
    @Published var clipboardSwitchToEnglishInput: Bool { didSet { save(clipboardSwitchToEnglishInput, Key.clipEnglishInput) } }
    @Published var workflowSwitchToEnglishInput: Bool { didSet { save(workflowSwitchToEnglishInput, Key.workflowEnglishInput) } }
    @Published var frecencyHalfLifeDays: Int { didSet { save(frecencyHalfLifeDays, Key.halfLife) } }
    // Opens the Workflow panel (⌘Space). Launchpad has no global shortcut (pinch / menu bar).
    @Published var workflowPanelHotKey: KeyCombo? { didSet { saveCombo(workflowPanelHotKey, Key.workflowHotKey) } }
    // Liquid Glass on controls (search field, page indicator).
    @Published var glassControls: Bool { didSet { save(glassControls, Key.glassControls) } }
    // Four-finger pinch in opens Launchpad, spread closes it.
    @Published var pinchToOpen: Bool { didSet { save(pinchToOpen, Key.pinchToOpen) } }
    // Launchpad / Clipboard / Workflow panel open on the display under the mouse; off = main display.
    @Published var panelsFollowMouseScreen: Bool { didSet { save(panelsFollowMouseScreen, Key.followMouseScreen) } }
    // Esc in AppPad / Clipboard / Workflow panel: on = clear the search first, close on the next press;
    // off (default) = close right away.
    @Published var escClearsSearchFirst: Bool { didSet { save(escClearsSearchFirst, Key.escClearsFirst) } }
    @Published var appHotKeys: [AppHotKey] {
        didSet { save((try? JSONEncoder().encode(appHotKeys)) ?? Data(), Key.appHotKeys) }
    }

    // MARK: Clipboard
    @Published var clipboardEnabled: Bool { didSet { save(clipboardEnabled, Key.clipEnabled) } }
    @Published var clipboardHotKey: KeyCombo? { didSet { saveCombo(clipboardHotKey, Key.clipHotKey) } }
    @Published var clipboardSavedHotKey: KeyCombo? { didSet { saveCombo(clipboardSavedHotKey, Key.clipSavedHotKey) } }
    @Published var clipboardWidthPercent: Int { didSet { updatePanelMatch(); save(clipboardWidthPercent, Key.clipWidth) } }
    @Published var clipboardHeightPercent: Int { didSet { updatePanelMatch(); save(clipboardHeightPercent, Key.clipHeight) } }
    @Published var clipboardSearchFontFamily: String { didSet { save(clipboardSearchFontFamily, Key.clipSearchFamily) } }
    @Published var clipboardSearchFontSize: Int { didSet { save(clipboardSearchFontSize, Key.clipSearchSize) } }
    @Published var clipboardListFontFamily: String { didSet { save(clipboardListFontFamily, Key.clipListFamily) } }
    @Published var clipboardListFontSize: Int { didSet { save(clipboardListFontSize, Key.clipListSize) } }
    @Published var clipboardHistoryLimit: Int { didSet { save(clipboardHistoryLimit, Key.clipLimit) } }     // 0 = unlimited
    @Published var clipboardRetentionDays: Int { didSet { save(clipboardRetentionDays, Key.clipDays) } }   // 0 = forever
    @Published var clipboardImageQuality: Int { didSet { save(clipboardImageQuality, Key.clipQuality) } }  // HEIC %, 50–100
    @Published var clipboardAutoPaste: Bool { didSet { save(clipboardAutoPaste, Key.clipAutoPaste) } }
    @Published var clipboardIgnoredApps: [String] { didSet { save(clipboardIgnoredApps, Key.clipIgnored) } }
    @Published var clipboardBackground: BackgroundSettings { didSet { saveBackground(clipboardBackground, Key.clipBackgroundV2) } }

    // MARK: Workflow panel
    @Published var workflowBackground: BackgroundSettings { didSet { saveBackground(workflowBackground, Key.workflowBackground) } }
    // On (default): same size and position as the Clipboard panel.
    @Published var workflowFollowsClipboardSize: Bool {
        didSet {
            // Turning it off starts from the Clipboard's current size (no jump).
            if !workflowFollowsClipboardSize && oldValue {
                workflowWidthPercent = clipboardWidthPercent
                workflowHeightPercent = clipboardHeightPercent
            }
            updatePanelMatch()
            save(workflowFollowsClipboardSize, Key.workflowFollowsClipSize)
        }
    }
    @Published var workflowWidthPercent: Int { didSet { updatePanelMatch(); save(workflowWidthPercent, Key.workflowWidth) } }
    @Published var workflowHeightPercent: Int { didSet { updatePanelMatch(); save(workflowHeightPercent, Key.workflowHeight) } }

    // AppPad %, Clipboard and Workflows width / height all equal → AppPad drops its +6% height.
    // Updated whenever one of these values changes (not when AppPad opens).
    @Published private(set) var launchpadMatchesPanels = false

    // MARK: Window control
    @Published var windowControlEnabled: Bool { didSet { save(windowControlEnabled, Key.winEnabled) } }
    // Missing entry = shortcut cleared by the user.
    @Published var windowHotKeys: [WindowAction: KeyCombo] {
        didSet {
            for action in WindowAction.allCases {
                let data = windowHotKeys[action].flatMap { try? JSONEncoder().encode($0) } ?? Data()
                defaults.set(data, forKey: Key.winHotKeyPrefix + action.rawValue)
            }
            NotificationCenter.default.post(name: .preferencesDidChange, object: self)
        }
    }

    private init() {
        let d = UserDefaults.standard
        openPagePolicy = OpenPagePolicy(rawValue: d.string(forKey: Key.openPage) ?? "") ?? .lastPage
        pageIndicatorStyle = PageIndicatorStyle(rawValue: d.string(forKey: Key.indicator) ?? "") ?? .dots
        gridColumns = d.object(forKey: Key.columns) as? Int ?? 7
        gridRows = d.object(forKey: Key.rows) as? Int ?? 5
        for key in Key.legacySizeKeys { d.removeObject(forKey: key) }
        windowPercent = d.object(forKey: Key.percent) as? Int ?? 100
        launchpadCoversMenuBar = d.object(forKey: Key.coverMenuBar) as? Bool ?? true
        appTheme = AppTheme(rawValue: d.string(forKey: Key.theme) ?? "") ?? .auto
        launchpadBackground = Self.loadBackground(d, Key.launchpadBackground) ?? Self.migrateLaunchpadBackground(d)
        backgroundClickAction = BackgroundClickAction(rawValue: d.string(forKey: Key.backgroundClick) ?? "") ?? .closePanel
        switchToEnglishInput = d.object(forKey: Key.englishInput) as? Bool ?? false
        clipboardSwitchToEnglishInput = d.object(forKey: Key.clipEnglishInput) as? Bool ?? false
        workflowSwitchToEnglishInput = d.object(forKey: Key.workflowEnglishInput) as? Bool ?? false
        frecencyHalfLifeDays = d.object(forKey: Key.halfLife) as? Int ?? 72
        glassControls = d.object(forKey: Key.glassControls) as? Bool ?? true
        pinchToOpen = d.object(forKey: Key.pinchToOpen) as? Bool ?? true
        panelsFollowMouseScreen = d.object(forKey: Key.followMouseScreen) as? Bool ?? true
        escClearsSearchFirst = d.object(forKey: Key.escClearsFirst) as? Bool ?? false
        workflowPanelHotKey = Self.loadCombo(d, Key.workflowHotKey, default: .defaultWorkflowPanel)
        clipboardEnabled = d.object(forKey: Key.clipEnabled) as? Bool ?? true
        clipboardHotKey = Self.loadCombo(d, Key.clipHotKey, default: .defaultClipboard)
        clipboardSavedHotKey = Self.loadCombo(d, Key.clipSavedHotKey, default: .defaultClipboardSaved)
        clipboardWidthPercent = Self.panelPercent(d.object(forKey: Key.clipWidth) as? Int)
        clipboardHeightPercent = Self.panelPercent(d.object(forKey: Key.clipHeight) as? Int)
        clipboardSearchFontFamily = d.string(forKey: Key.clipSearchFamily) ?? ""
        clipboardSearchFontSize = d.object(forKey: Key.clipSearchSize) as? Int ?? 18
        clipboardListFontFamily = d.string(forKey: Key.clipListFamily) ?? ""
        clipboardListFontSize = d.object(forKey: Key.clipListSize) as? Int ?? 15
        // Kept forever by default; old items are removed with the "Delete …" buttons in Settings.
        clipboardHistoryLimit = d.object(forKey: Key.clipLimit) as? Int ?? 0
        clipboardRetentionDays = d.object(forKey: Key.clipDays) as? Int ?? 0
        clipboardImageQuality = d.object(forKey: Key.clipQuality) as? Int ?? 85
        clipboardAutoPaste = d.object(forKey: Key.clipAutoPaste) as? Bool ?? true
        clipboardIgnoredApps = d.stringArray(forKey: Key.clipIgnored)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        clipboardBackground = Self.loadBackground(d, Key.clipBackgroundV2) ?? Self.migrateClipboardBackground(d)
        workflowBackground = Self.loadBackground(d, Key.workflowBackground) ?? .panelDefault   // always followed AppPad before
        workflowFollowsClipboardSize = d.object(forKey: Key.workflowFollowsClipSize) as? Bool ?? true
        workflowWidthPercent = Self.panelPercent(d.object(forKey: Key.workflowWidth) as? Int)
        workflowHeightPercent = Self.panelPercent(d.object(forKey: Key.workflowHeight) as? Int)
        windowControlEnabled = d.object(forKey: Key.winEnabled) as? Bool ?? true
        var windowCombos: [WindowAction: KeyCombo] = [:]
        for action in WindowAction.allCases {
            windowCombos[action] = Self.loadCombo(d, Key.winHotKeyPrefix + action.rawValue, default: action.defaultCombo)
        }
        windowHotKeys = windowCombos
        if let data = d.data(forKey: Key.appHotKeys),
           let decoded = try? JSONDecoder().decode([AppHotKey].self, from: data) {
            appHotKeys = decoded
        } else {
            appHotKeys = []
        }
        updatePanelMatch()
    }

    // Clipboard / Workflow panel size limits (percent of the screen's visible frame).
    static let panelPercentRange = 40...100
    static let panelPercentDefault = 60

    private static func panelPercent(_ stored: Int?) -> Int {
        min(max(stored ?? panelPercentDefault, panelPercentRange.lowerBound), panelPercentRange.upperBound)
    }

    // Size actually used by the Workflow panel (may follow the Clipboard).
    var workflowPanelPercent: (width: Int, height: Int) {
        workflowFollowsClipboardSize
            ? (clipboardWidthPercent, clipboardHeightPercent)
            : (workflowWidthPercent, workflowHeightPercent)
    }

    // Recomputed by the AppPad / Clipboard / Workflows size setters (before they post the change).
    private func updatePanelMatch() {
        let p = windowPercent
        let workflow = workflowPanelPercent
        let matches = clipboardWidthPercent == p && clipboardHeightPercent == p
            && workflow.width == p && workflow.height == p
        if matches != launchpadMatchesPanels { launchpadMatchesPanels = matches }
    }

    // Background actually used by a panel (Clipboard / Workflows may follow AppPad).
    func effectiveBackground(for surface: BackgroundSurface) -> BackgroundSettings {
        switch surface {
        case .launchpad: return launchpadBackground
        case .clipboard: return clipboardBackground.follow ? launchpadBackground : clipboardBackground
        case .workflows: return workflowBackground.follow ? launchpadBackground : workflowBackground
        }
    }

    private static func loadBackground(_ d: UserDefaults, _ key: String) -> BackgroundSettings? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BackgroundSettings.self, from: data)
    }

    private func saveBackground(_ settings: BackgroundSettings, _ key: String) {
        save((try? JSONEncoder().encode(settings)) ?? Data(), key)
    }

    // Old "backgroundStyle" (wallpaper / white); only an explicit wallpaper choice is kept.
    private static func migrateLaunchpadBackground(_ d: UserDefaults) -> BackgroundSettings {
        var settings = BackgroundSettings.launchpadDefault
        if d.string(forKey: Key.legacyBackground) == "wallpaper" { settings.style = .wallpaper }
        return settings
    }

    // Old clipboard enum (followLaunchpad / wallpaper / heavyBlur / white / lightGray / darkGray / custom).
    private static func migrateClipboardBackground(_ d: UserDefaults) -> BackgroundSettings {
        var settings = BackgroundSettings.panelDefault
        if let hex = d.string(forKey: Key.legacyClipBackgroundColor) {
            for variant in ThemeVariant.allCases { settings.customColors[variant.rawValue] = hex }
        }
        guard let old = d.string(forKey: Key.legacyClipBackground), old != "followLaunchpad" else { return settings }
        settings.follow = false
        switch old {
        case "heavyBlur":
            settings.style = .wallpaper
            for variant in ThemeVariant.allCases {
                var tuning = BackgroundPalette.defaultTuning(.wallpaper, variant)
                tuning.blur = 0.9
                settings.setTuning(tuning, .wallpaper, variant)
            }
        default:
            settings.style = BackgroundStyle(rawValue: old) ?? .wallpaper
        }
        return settings
    }

    // Empty data = explicitly cleared; missing key = use default.
    private static func loadCombo(_ d: UserDefaults, _ key: String, default fallback: KeyCombo) -> KeyCombo? {
        guard let data = d.data(forKey: key) else { return fallback }
        return data.isEmpty ? nil : (try? JSONDecoder().decode(KeyCombo.self, from: data))
    }

    private func saveCombo(_ combo: KeyCombo?, _ key: String) {
        save(combo.flatMap { try? JSONEncoder().encode($0) } ?? Data(), key)
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: .preferencesDidChange, object: self)
    }
}
