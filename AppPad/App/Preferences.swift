import Foundation
import Combine

nonisolated enum OpenPagePolicy: String, CaseIterable, Sendable {
    case firstPage, lastPage
}

nonisolated enum PageIndicatorStyle: String, CaseIterable, Sendable {
    case dots, numbers
}

nonisolated enum WindowSizeMode: String, CaseIterable, Sendable {
    case screenPercent, custom
}

nonisolated enum BackgroundClickAction: String, CaseIterable, Sendable {
    case closePanel   // like clicking outside (macOS 15 Launchpad)
    case nothing
}

nonisolated enum PanelBackgroundStyle: String, CaseIterable, Sendable {
    case wallpaper   // blurred desktop picture (macOS 15 Launchpad look)
    case white
}

// Clipboard panel background; independent of the launcher unless followLaunchpad.
nonisolated enum ClipboardBackground: String, CaseIterable, Sendable {
    case followLaunchpad, wallpaper, heavyBlur, white, lightGray, darkGray, custom
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
        static let sizeMode = "windowSizeMode"
        static let percent = "windowPercent"
        static let width = "customWidth"
        static let height = "customHeight"
        static let background = "backgroundStyle"
        static let backgroundClick = "backgroundClickAction"
        static let englishInput = "switchToEnglishInput"
        static let halfLife = "frecencyHalfLifeDays"
        static let hotKey = "launcherHotKey"
        static let appHotKeys = "appHotKeys"
        static let glassControls = "glassControls"
        static let pinchToOpen = "pinchToOpen"
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
        static let clipBackground = "clipboardBackground"
        static let clipBackgroundColor = "clipboardBackgroundColor"
        static let winEnabled = "windowControlEnabled"
        static let winHotKeyPrefix = "windowHotKey."
    }

    @Published var openPagePolicy: OpenPagePolicy { didSet { save(openPagePolicy.rawValue, Key.openPage) } }
    @Published var pageIndicatorStyle: PageIndicatorStyle { didSet { save(pageIndicatorStyle.rawValue, Key.indicator) } }
    @Published var gridColumns: Int { didSet { save(gridColumns, Key.columns) } }
    @Published var gridRows: Int { didSet { save(gridRows, Key.rows) } }
    @Published var windowSizeMode: WindowSizeMode { didSet { save(windowSizeMode.rawValue, Key.sizeMode) } }
    @Published var windowPercent: Int { didSet { save(windowPercent, Key.percent) } }
    @Published var customWidth: Int { didSet { save(customWidth, Key.width) } }
    @Published var customHeight: Int { didSet { save(customHeight, Key.height) } }
    @Published var backgroundStyle: PanelBackgroundStyle { didSet { save(backgroundStyle.rawValue, Key.background) } }
    @Published var backgroundClickAction: BackgroundClickAction { didSet { save(backgroundClickAction.rawValue, Key.backgroundClick) } }
    @Published var switchToEnglishInput: Bool { didSet { save(switchToEnglishInput, Key.englishInput) } }
    @Published var frecencyHalfLifeDays: Int { didSet { save(frecencyHalfLifeDays, Key.halfLife) } }
    @Published var launcherHotKey: KeyCombo? { didSet { saveCombo(launcherHotKey, Key.hotKey) } }
    // Liquid Glass on controls (search field, page indicator).
    @Published var glassControls: Bool { didSet { save(glassControls, Key.glassControls) } }
    // Four-finger pinch in opens Launchpad, spread closes it.
    @Published var pinchToOpen: Bool { didSet { save(pinchToOpen, Key.pinchToOpen) } }
    @Published var appHotKeys: [AppHotKey] {
        didSet { save((try? JSONEncoder().encode(appHotKeys)) ?? Data(), Key.appHotKeys) }
    }

    // MARK: Clipboard
    @Published var clipboardEnabled: Bool { didSet { save(clipboardEnabled, Key.clipEnabled) } }
    @Published var clipboardHotKey: KeyCombo? { didSet { saveCombo(clipboardHotKey, Key.clipHotKey) } }
    @Published var clipboardSavedHotKey: KeyCombo? { didSet { saveCombo(clipboardSavedHotKey, Key.clipSavedHotKey) } }
    @Published var clipboardWidthPercent: Int { didSet { save(clipboardWidthPercent, Key.clipWidth) } }
    @Published var clipboardHeightPercent: Int { didSet { save(clipboardHeightPercent, Key.clipHeight) } }
    @Published var clipboardSearchFontFamily: String { didSet { save(clipboardSearchFontFamily, Key.clipSearchFamily) } }
    @Published var clipboardSearchFontSize: Int { didSet { save(clipboardSearchFontSize, Key.clipSearchSize) } }
    @Published var clipboardListFontFamily: String { didSet { save(clipboardListFontFamily, Key.clipListFamily) } }
    @Published var clipboardListFontSize: Int { didSet { save(clipboardListFontSize, Key.clipListSize) } }
    @Published var clipboardHistoryLimit: Int { didSet { save(clipboardHistoryLimit, Key.clipLimit) } }     // 0 = unlimited
    @Published var clipboardRetentionDays: Int { didSet { save(clipboardRetentionDays, Key.clipDays) } }   // 0 = forever
    @Published var clipboardImageQuality: Int { didSet { save(clipboardImageQuality, Key.clipQuality) } }  // HEIC %, 50–100
    @Published var clipboardAutoPaste: Bool { didSet { save(clipboardAutoPaste, Key.clipAutoPaste) } }
    @Published var clipboardIgnoredApps: [String] { didSet { save(clipboardIgnoredApps, Key.clipIgnored) } }
    @Published var clipboardBackground: ClipboardBackground { didSet { save(clipboardBackground.rawValue, Key.clipBackground) } }
    @Published var clipboardBackgroundColor: String { didSet { save(clipboardBackgroundColor, Key.clipBackgroundColor) } }  // "#RRGGBB" for .custom

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
        windowSizeMode = WindowSizeMode(rawValue: d.string(forKey: Key.sizeMode) ?? "") ?? .screenPercent
        windowPercent = d.object(forKey: Key.percent) as? Int ?? 100
        customWidth = d.object(forKey: Key.width) as? Int ?? 1280
        customHeight = d.object(forKey: Key.height) as? Int ?? 800
        backgroundStyle = PanelBackgroundStyle(rawValue: d.string(forKey: Key.background) ?? "") ?? .wallpaper
        backgroundClickAction = BackgroundClickAction(rawValue: d.string(forKey: Key.backgroundClick) ?? "") ?? .closePanel
        switchToEnglishInput = d.object(forKey: Key.englishInput) as? Bool ?? true
        frecencyHalfLifeDays = d.object(forKey: Key.halfLife) as? Int ?? 72
        glassControls = d.object(forKey: Key.glassControls) as? Bool ?? true
        pinchToOpen = d.object(forKey: Key.pinchToOpen) as? Bool ?? true
        launcherHotKey = Self.loadCombo(d, Key.hotKey, default: .defaultLauncher)
        clipboardEnabled = d.object(forKey: Key.clipEnabled) as? Bool ?? true
        clipboardHotKey = Self.loadCombo(d, Key.clipHotKey, default: .defaultClipboard)
        clipboardSavedHotKey = Self.loadCombo(d, Key.clipSavedHotKey, default: .defaultClipboardSaved)
        clipboardWidthPercent = d.object(forKey: Key.clipWidth) as? Int ?? 60
        clipboardHeightPercent = d.object(forKey: Key.clipHeight) as? Int ?? 60
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
        clipboardBackground = ClipboardBackground(rawValue: d.string(forKey: Key.clipBackground) ?? "") ?? .followLaunchpad
        clipboardBackgroundColor = d.string(forKey: Key.clipBackgroundColor) ?? "#3A3A3C"
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
