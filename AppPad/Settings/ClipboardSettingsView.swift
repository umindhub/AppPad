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
                LabeledContent("Clipboard shortcut") {
                    ShortcutRecorder(combo: $prefs.clipboardHotKey)
                        .frame(width: 170, height: 24)
                }
                LabeledContent("Saved items shortcut") {
                    ShortcutRecorder(combo: $prefs.clipboardSavedHotKey)
                        .frame(width: 170, height: 24)
                }
                Toggle("Paste directly into the active app", isOn: $prefs.clipboardAutoPaste)
                if prefs.clipboardAutoPaste && !trusted {
                    HStack {
                        Text("Needs Accessibility permission; until then items are only copied.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Grant Access…") {
                            PasteService.requestAccess()
                            PasteService.openAccessibilitySettings()
                        }
                    }
                }
                Text("⌘⇧J / ⌘⇧K switch between AppPad and Clipboard; the Saved button (or the saved items shortcut) shows saved items only. ⌘1–⌘0 paste the first ten items, ⌘J / ⌘K move like ↓ / ↑, ⌘S saves, ⌘⌫ deletes. Type \"App::text\" to filter by app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Window") {
                Picker("Background", selection: $prefs.clipboardBackground) {
                    Text("Same as AppPad").tag(ClipboardBackground.followLaunchpad)
                    Text("Blurred wallpaper").tag(ClipboardBackground.wallpaper)
                    Text("Heavily blurred wallpaper").tag(ClipboardBackground.heavyBlur)
                    Text("White").tag(ClipboardBackground.white)
                    Text("Light gray").tag(ClipboardBackground.lightGray)
                    Text("Dark gray").tag(ClipboardBackground.darkGray)
                    Text("Custom color").tag(ClipboardBackground.custom)
                }
                if prefs.clipboardBackground == .custom {
                    ColorPicker("Color", selection: customColor, supportsOpacity: false)
                }
                percentSlider("Width", value: $prefs.clipboardWidthPercent)
                percentSlider("Height", value: $prefs.clipboardHeightPercent)
            }

            Section("Fonts") {
                fontPicker("Search font", family: $prefs.clipboardSearchFontFamily)
                Stepper("Search size: \(prefs.clipboardSearchFontSize) pt",
                        value: $prefs.clipboardSearchFontSize, in: 11...40)
                fontPicker("List font", family: $prefs.clipboardListFontFamily)
                Stepper("List size: \(prefs.clipboardListFontSize) pt",
                        value: $prefs.clipboardListFontSize, in: 11...40)
            }

            Section("History") {
                Picker("Keep up to", selection: $prefs.clipboardHistoryLimit) {
                    ForEach(Self.limits, id: \.self) { limit in
                        (limit == 0 ? Text("Unlimited") : Text("\(limit) items")).tag(limit)
                    }
                }
                Picker("Keep for", selection: $prefs.clipboardRetentionDays) {
                    ForEach(Self.retention, id: \.self) { days in
                        (days == 0 ? Text("Forever") : Text("\(days) days")).tag(days)
                    }
                }
                LabeledContent("Image quality (HEIC)") {
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
                Text("Saved items are never removed by these limits.")
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
                LabeledContent("All history") {
                    HStack(spacing: 10) {
                        Text(totalCount, format: .number)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Button("Delete…") { confirmDeleteAll = true }
                            .disabled(totalCount == 0)
                    }
                }
            } header: {
                Text("Delete History")
            } footer: {
                Text("Saved items are never deleted here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ignored Apps") {
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
        .alert("Delete clipboard history?", isPresented: $confirmDelete, presenting: pendingDelete) { range in
            Button("Delete \(counts[range] ?? 0) Items", role: .destructive) {
                maintenance.delete(range)
                refreshCounts()
            }
            Button("Cancel", role: .cancel) {}
        } message: { range in
            Text("\(Self.title(for: range)). Saved items are kept.")
        }
        .alert("Delete all clipboard history?", isPresented: $confirmDeleteAll) {
            Button("Delete \(totalCount) Items", role: .destructive) {
                maintenance.delete(nil)
                refreshCounts()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saved items are kept.")
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
        case .olderThanYear: return String(localized: "Older than 1 year")
        case .sixToTwelveMonths: return String(localized: "6 months – 1 year ago")
        case .threeToSixMonths: return String(localized: "3 – 6 months ago")
        case .lastWeek: return String(localized: "Last 7 days")
        case .lastDay: return String(localized: "Last 24 hours")
        case .lastHour: return String(localized: "Last hour")
        }
    }

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: ClipboardColors.color(hex: prefs.clipboardBackgroundColor) ?? ClipboardColors.darkGray) },
            set: { prefs.clipboardBackgroundColor = ClipboardColors.hex(NSColor($0)) }
        )
    }

    private func percentSlider(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(
                    value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                    in: 30...100,
                    step: 5
                )
                Text(Double(value.wrappedValue) / 100, format: .percent)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .frame(width: 220)
        }
    }

    private func fontPicker(_ title: LocalizedStringKey, family: Binding<String>) -> some View {
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
