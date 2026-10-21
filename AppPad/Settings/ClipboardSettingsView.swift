import SwiftUI
import AppKit
import UniformTypeIdentifiers

// History cleanup hooks (count / delete by range, nil = all). Saved items are never affected.
struct ClipboardMaintenance {
    var count: (ClipAgeRange?) -> Int
    var delete: (ClipAgeRange?) -> Void
}

// Settings → Clipboard tab.
struct ClipboardSettingsView: View {
    @ObservedObject var prefs: Preferences
    var maintenance: ClipboardMaintenance
    @State private var trusted = PasteService.isTrusted
    @State private var counts: [ClipAgeRange: Int] = [:]
    @State private var totalCount = 0
    @State private var pendingDelete: ClipAgeRange?
    @State private var confirmDelete = false
    @State private var confirmDeleteAll = false

    private static let fontFamilies = NSFontManager.shared.availableFontFamilies
    private static let limits = [0, 1000, 5000, 20000]
    private static let retention = [0, 30, 90, 365]
    // Button order: oldest first, then the most recent ranges.
    private static let ranges: [ClipAgeRange] = [
        .olderThanYear, .sixToTwelveMonths, .threeToSixMonths, .lastWeek, .lastDay, .lastHour,
    ]

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable clipboard history", isOn: $prefs.clipboardEnabled)
                LabeledContent(String(localized: "Clipboard shortcut", table: "Clipboard")) {
                    ShortcutRecorder(combo: $prefs.clipboardHotKey)
                        .frame(width: 170, height: 24)
                }
                LabeledContent(String(localized: "Saved items shortcut", table: "Clipboard")) {
                    ShortcutRecorder(combo: $prefs.clipboardSavedHotKey)
                        .frame(width: 170, height: 24)
                }
                Toggle("Switch to English input when opened", isOn: $prefs.clipboardSwitchToEnglishInput)
                Toggle(String(localized: "Paste directly into the active app", table: "Clipboard"), isOn: $prefs.clipboardAutoPaste)
                if prefs.clipboardAutoPaste && !trusted {
                    HStack {
                        Text("Needs Accessibility permission; until then items are only copied.", tableName: "Clipboard")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access…") {
                            PasteService.requestAccess()
                            PasteService.openAccessibilitySettings()
                        }
                    }
                }
                Text("⌘⇧K / ⌘⇧J switch between AppPad, Workflows and Clipboard; the Saved button (or the saved items shortcut) shows saved items only. ⌘1–⌘0 paste the first ten items, ⌘K / ⌘J move like ↑ / ↓, ⌘S saves, ⌘⇧⌫ deletes. Type \"App::text\" to filter by app.", tableName: "Clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Window") {
                PanelPercentSlider(title: "Width", value: $prefs.clipboardWidthPercent)
                PanelPercentSlider(title: "Height", value: $prefs.clipboardHeightPercent)
            }

            BackgroundSection(settings: $prefs.clipboardBackground, allowsFollow: true)

            Section(String(localized: "Fonts", table: "Clipboard")) {
                fontPicker(String(localized: "Search font", table: "Clipboard"), family: $prefs.clipboardSearchFontFamily)
                Stepper(String(localized: "Search size: \(prefs.clipboardSearchFontSize) pt", table: "Clipboard"),
                        value: $prefs.clipboardSearchFontSize, in: 11...40)
                fontPicker(String(localized: "List font", table: "Clipboard"), family: $prefs.clipboardListFontFamily)
                Stepper(String(localized: "List size: \(prefs.clipboardListFontSize) pt", table: "Clipboard"),
                        value: $prefs.clipboardListFontSize, in: 11...40)
            }

            Section(String(localized: "History", table: "Clipboard")) {
                Picker(String(localized: "Keep up to", table: "Clipboard"), selection: $prefs.clipboardHistoryLimit) {
                    ForEach(Self.limits, id: \.self) { limit in
                        (limit == 0 ? Text("Unlimited", tableName: "Clipboard") : Text("\(limit) items")).tag(limit)
                    }
                }
                Picker(String(localized: "Keep for", table: "Clipboard"), selection: $prefs.clipboardRetentionDays) {
                    ForEach(Self.retention, id: \.self) { days in
                        (days == 0 ? Text("Forever", tableName: "Clipboard") : Text("\(days) days", tableName: "Clipboard")).tag(days)
                    }
                }
                LabeledContent(String(localized: "Image quality (HEIC)", table: "Clipboard")) {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { Double(prefs.clipboardImageQuality) },
                                set: { prefs.clipboardImageQuality = Int($0.rounded()) }
                            ),
                            in: 50...100,
                            step: 5
                        )
                        Text(Double(prefs.clipboardImageQuality) / 100, format: .percent)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    .frame(width: 220)
                }
                Text("Saved items are never removed by these limits.", tableName: "Clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(Self.ranges, id: \.self) { range in
                    LabeledContent(Self.title(for: range)) {
                        HStack(spacing: 10) {
                            Text(counts[range] ?? 0, format: .number)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Button("Delete…") {
                                pendingDelete = range
                                confirmDelete = true
                            }
                            .disabled((counts[range] ?? 0) == 0)
                        }
                    }
                }
                LabeledContent(String(localized: "All history", table: "Clipboard")) {
                    HStack(spacing: 10) {
                        Text(totalCount, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Delete…") { confirmDeleteAll = true }
                            .disabled(totalCount == 0)
                    }
                }
            } header: {
                Text("Delete History", tableName: "Clipboard")
            } footer: {
                Text("Saved items are never deleted here.", tableName: "Clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "Ignored Apps", table: "Clipboard")) {
                ForEach(prefs.clipboardIgnoredApps, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                                .lineLimit(1)
                        } else {
                            Text(bundleID)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            prefs.clipboardIgnoredApps.removeAll { $0 == bundleID }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add App…", action: addIgnoredApps)
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            trusted = PasteService.isTrusted
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardStoreDidChange)) { _ in
            refreshCounts()
        }
        .onAppear {
            trusted = PasteService.isTrusted
            refreshCounts()
        }
        .alert(String(localized: "Delete clipboard history?", table: "Clipboard"), isPresented: $confirmDelete, presenting: pendingDelete) { range in
            Button(String(localized: "Delete \(counts[range] ?? 0) Items", table: "Clipboard"), role: .destructive) {
                maintenance.delete(range)
                refreshCounts()
            }
            Button("Cancel", role: .cancel) {}
        } message: { range in
            Text("\(Self.title(for: range)). Saved items are kept.", tableName: "Clipboard")
        }
        .alert(String(localized: "Delete all clipboard history?", table: "Clipboard"), isPresented: $confirmDeleteAll) {
            Button(String(localized: "Delete \(totalCount) Items", table: "Clipboard"), role: .destructive) {
                maintenance.delete(nil)
                refreshCounts()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved items are kept.", tableName: "Clipboard")
        }
    }

    private func refreshCounts() {
        var result: [ClipAgeRange: Int] = [:]
        for range in Self.ranges { result[range] = maintenance.count(range) }
        counts = result
        totalCount = maintenance.count(nil)
    }

    private static func title(for range: ClipAgeRange) -> String {
        switch range {
        case .olderThanYear: return String(localized: "Older than 1 year", table: "Clipboard")
        case .sixToTwelveMonths: return String(localized: "6 months – 1 year ago", table: "Clipboard")
        case .threeToSixMonths: return String(localized: "3 – 6 months ago", table: "Clipboard")
        case .lastWeek: return String(localized: "Last 7 days", table: "Clipboard")
        case .lastDay: return String(localized: "Last 24 hours", table: "Clipboard")
        case .lastHour: return String(localized: "Last hour", table: "Clipboard")
        }
    }

    private func fontPicker(_ title: String, family: Binding<String>) -> some View {
        Picker(title, selection: family) {
            Text("System").tag("")
            Divider()
            ForEach(Self.fontFamilies, id: \.self) { name in
                Text(name).tag(name)
            }
        }
    }

    private func addIgnoredApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !prefs.clipboardIgnoredApps.contains(id) else { continue }
            prefs.clipboardIgnoredApps.append(id)
        }
    }
}

// Clipboard / Workflow window size slider: percent of the screen, 40–100%.
struct PanelPercentSlider: View {
    var title: LocalizedStringKey
    @Binding var value: Int

    var body: some View {
        LabeledContent(title) {
            HStack {
                Slider(
                    value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                    in: Double(Preferences.panelPercentRange.lowerBound)...Double(Preferences.panelPercentRange.upperBound),
                    step: 5
                )
                Text(Double(value) / 100, format: .percent)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: 220)
        }
    }
}
