import AppKit

// Workflows shipped with AppPad (group "system"). Bump a version to push changes to installed copies. Installed on launch; a higher version here
// replaces the installed one. They can't be edited or deleted, only disabled.
// Names / descriptions / hints are English keys; translations come from Localizable.
enum BuiltinWorkflows {
    static let group = "system"
    // One shortcut for both (same approach as Alfred): input "timer\n<seconds>" or "alarm\n<HH:mm>[\n<label>]".
    // Shipped signed in the app bundle; imported once, then run in the background via `shortcuts run`.
    static let clockShortcut = "AppPad Clock"

    // Built-ins deleted before they became undeletable: added back once, disabled.
    private static let legacyRemovedKey = "AppPad.removedBuiltinWorkflows"

    static var identifiers: Set<String> { Set(all.map(\.identifier)) }

    static var all: [Workflow] {
        [
            // No success notice: Finder plays its own empty-trash sound.
            make("com.youmindhub.emptytrash", "Empty Trash", "Empty the Trash.",
                 version: "1.3", keywords: ["trash", "emptytrash", "bin"], symbol: "trash",
                 steps: [WorkflowStep(builtin: .emptyTrash, timeout: 300)]),
            make("com.youmindhub.timer", "Set Timer", "Start a timer in the Clock app.",
                 version: "1.3", keywords: ["time", "timer", "countdown"], symbol: "timer",
                 argument: .required, type: .duration, hint: "duration",
                 steps: [shortcutStep(clockShortcut, input: "timer\\n{{input}}")]),
            make("com.youmindhub.alarm", "Set Alarm", "Create an alarm in the Clock app.",
                 version: "1.3", keywords: ["alarm", "wake", "clock"], symbol: "alarm",
                 argument: .required, type: .time, hint: "time [label]",
                 steps: [shortcutStep(clockShortcut, input: "alarm\\n{{input}}")]),
            make("com.youmindhub.reminder", "Set Reminder",
                 "Add a reminder to the Reminders app. Dates like “tomorrow 3pm” set an alert; !–!!! sets the priority, @List picks a list.",
                 version: "1.2", keywords: ["remind", "reminder", "todo"], symbol: "checklist", notice: .output,
                 argument: .required, type: .reminder, hint: "reminder",
                 steps: [WorkflowStep(builtin: .createReminder, timeout: 30)]),
            make("com.youmindhub.shutdown", "Shut Down", "Show the system’s Shut Down dialog.",
                 version: "1.2", keywords: ["shutdown", "poweroff", "halt"], symbol: "power",
                 steps: [WorkflowStep(builtin: .shutDown, timeout: 20)]),
            make("com.youmindhub.restart", "Restart", "Show the system’s Restart dialog.",
                 version: "1.4", keywords: ["restart", "reboot"], symbol: "arrow.clockwise",
                 steps: [WorkflowStep(builtin: .restart, timeout: 20)]),
            make("com.youmindhub.sleepdisplays", "Sleep Displays", "Turn off the displays now.",
                 version: "1.2", keywords: ["display", "displayoff", "screenoff"], symbol: "display",
                 steps: [WorkflowStep(builtin: .sleepDisplays, timeout: 10)]),
            make("com.youmindhub.sleep", "Sleep Mac", "Put the Mac to sleep now.",
                 version: "1.2", keywords: ["sleep", "suspend"], symbol: "moon.zzz",
                 steps: [WorkflowStep(builtin: .sleepMac, timeout: 10)]),
            make("com.youmindhub.keepawake", "Keep Awake", "Keep the Mac awake; without a duration until you stop it.",
                 version: "1.2", keywords: ["awake", "caffeinate", "nosleep"], symbol: "cup.and.saucer", notice: .output,
                 argument: .optional, type: .duration, hint: "duration",
                 steps: [WorkflowStep(builtin: .keepAwake)]),
            make("com.youmindhub.darkmode", "Toggle Light/Dark Mode", "Switch between light and dark appearance.",
                 version: "1.3", keywords: ["dark", "light", "theme", "appearance"], symbol: "circle.lefthalf.filled",
                 steps: [WorkflowStep(builtin: .toggleDarkMode, timeout: 20)]),
            make("com.youmindhub.volume", "Set Volume", "Set the output volume.",
                 version: "1.4", keywords: ["vol", "volume", "sound"], symbol: "speaker.wave.2",
                 argument: .required, type: .percent, hint: "0–100",
                 steps: [WorkflowStep(builtin: .setVolume, timeout: 10)]),
            make("com.youmindhub.mute", "Toggle Mute", "Mute or unmute the sound output.",
                 version: "1.3", keywords: ["mute", "unmute"], symbol: "speaker.slash",
                 steps: [WorkflowStep(builtin: .toggleMute, timeout: 10)]),
            make("com.youmindhub.eject", "Eject All Disks", "Eject external disks and disk images.",
                 version: "1.2", keywords: ["eject", "unmount"], symbol: "eject", notice: .output,
                 steps: [WorkflowStep(builtin: .ejectDisks, timeout: 120)]),
            make("com.youmindhub.hiddenfiles", "Toggle Hidden Files", "Show or hide hidden files in Finder.",
                 version: "1.2", keywords: ["hidden", "dotfiles", "showhidden"], symbol: "eye", notice: .output,
                 steps: [WorkflowStep(builtin: .toggleHiddenFiles, timeout: 20)]),
            // Same identifier as the old "Quit App" (by name): the higher version replaces installed copies.
            // Asks first: Tab / ↩ in the panel would otherwise quit everything at once.
            make("com.youmindhub.quit", "Quit All Apps", "Quit all running apps. Finder and AppPad stay open.",
                 version: "1.4", keywords: ["quit", "close"], symbol: "xmark.app", notice: .output, confirm: true,
                 steps: [WorkflowStep(builtin: .quitAllApps, timeout: 30)]),
            make("com.youmindhub.websearch", "Google Search", "Search the web. Duplicate it and change the URL for other sites.",
                 version: "1.2", keywords: ["g", "google", "search"], symbol: "magnifyingglass",
                 argument: .required, type: .text, hint: "keywords",
                 steps: [openURLStep("https://www.google.com/search?q={{input}}")]),
            // Same URL Finder uses for "Search App Store…"; opens results right in the App Store app.
            // No argument case: the App Store app itself is in the panel.
            make("com.youmindhub.appstoresearch", "App Store Search", "Search the Mac App Store.",
                 version: "1.0", keywords: ["mas", "appstore", "appstoresearch"], symbol: "bag",
                 argument: .required, type: .text, hint: "keywords",
                 steps: [openURLStep("macappstores://search.itunes.apple.com/WebObjects/MZSearch.woa/wa/search?q={{input}}")]),
            make("com.youmindhub.ipaddress", "Copy IP Address", "Copy the local IP address and show the public one.",
                 version: "1.2", keywords: ["ip", "ipaddress", "myip"], symbol: "network", notice: .output,
                 steps: [WorkflowStep(builtin: .copyIPAddress, timeout: 10)]),
            make("com.youmindhub.uuid", "Generate UUID", "Copy a new UUID to the clipboard.",
                 version: "1.2", keywords: ["uuid", "guid"], symbol: "number", notice: .output, copy: true,
                 steps: [WorkflowStep(builtin: .generateUUID, timeout: 5)]),
            // Only AppPad's own entry in claude_desktop_config.json changes; other servers are kept.
            make("com.youmindhub.claudedesktop.add", "Add AppPad to Claude Desktop",
                 "Add AppPad's MCP server to Claude Desktop so Claude can run your workflows.",
                 version: "1.0", keywords: ["claude", "mcp", "addmcp"], symbol: "plus.circle", notice: .output,
                 steps: [WorkflowStep(builtin: .addToClaudeDesktop, timeout: 10)]),
            make("com.youmindhub.claudedesktop.remove", "Remove AppPad from Claude Desktop",
                 "Remove AppPad's MCP server from Claude Desktop. Other MCP servers are kept.",
                 version: "1.0", keywords: ["claude", "mcp", "removemcp"], symbol: "minus.circle", notice: .output,
                 steps: [WorkflowStep(builtin: .removeFromClaudeDesktop, timeout: 10)]),
            // YouMindHub's bundled MCP helper; only the "youmindhub" entry changes.
            make("com.youmindhub.claudedesktop.youmindhub.add", "Add YouMindHub to Claude Desktop",
                 "Add YouMindHub's MCP server to Claude Desktop so Claude can use YouMindHub.",
                 version: "1.0", keywords: ["youmindhub", "claude", "mcp", "addyoumindhub"], symbol: "plus.circle",
                 notice: .output,
                 steps: [WorkflowStep(builtin: .addYouMindHubToClaudeDesktop, timeout: 10)]),
            make("com.youmindhub.claudedesktop.youmindhub.remove", "Remove YouMindHub from Claude Desktop",
                 "Remove YouMindHub's MCP server from Claude Desktop. Other MCP servers are kept.",
                 version: "1.0", keywords: ["youmindhub", "claude", "mcp", "removeyoumindhub"], symbol: "minus.circle",
                 notice: .output,
                 steps: [WorkflowStep(builtin: .removeYouMindHubFromClaudeDesktop, timeout: 10)]),
            // Official command pre-filled in Terminal (user presses Return, password asked there).
            make("com.youmindhub.homebrew.install", "Install Homebrew",
                 "Open Terminal with Homebrew’s official install command filled in; press Return to start it. AI assistants use Homebrew to install apps.",
                 version: "1.1", keywords: ["brew", "homebrew", "installbrew"], symbol: "shippingbox",
                 notice: .output, confirm: true,
                 steps: [WorkflowStep(builtin: .installHomebrew, timeout: 10)]),
        ]
    }

    // MARK: - Install

    // Called once after the store loaded its files.
    static func install(into store: WorkflowStore) {
        let legacyRemoved = Set(UserDefaults.standard.stringArray(forKey: legacyRemovedKey) ?? [])
        for builtin in all {
            let existing = store.workflow(identifier: builtin.identifier)
            // A copy that isn't AppPad's own is always replaced by the shipped one.
            if let existing, existing.source.kind == .builtin {
                guard WorkflowIdentity.compareVersions(builtin.version, existing.version) == .orderedDescending else { continue }
            }
            store.install(builtin, source: .builtin)
            grantUndecided(builtin.identifier, in: store)
            // Deleted by the user in an earlier version: keep it off.
            if existing == nil, legacyRemoved.contains(builtin.identifier),
               var added = store.workflow(identifier: builtin.identifier) {
                added.enabled = false
                store.save(added)
            }
        }
        if !legacyRemoved.isEmpty { UserDefaults.standard.removeObject(forKey: legacyRemovedKey) }
    }

    // Backup restore: built-ins always come from the app, never from the backup file.
    // Adds the shipped one if it's missing; false for other identifiers.
    @discardableResult
    static func reinstall(_ identifier: String, into store: WorkflowStore) -> Bool {
        guard let builtin = all.first(where: { $0.identifier == identifier }) else { return false }
        if let existing = store.workflow(identifier: identifier), existing.source.kind == .builtin { return true }
        store.install(builtin, source: .builtin)
        grantUndecided(identifier, in: store)
        return true
    }

    // Store files from before sources were recorded: built-in ids are AppPad's own
    // (edited when they differ from the shipped behavior), everything else is the user's.
    static func legacySource(for workflow: Workflow) -> WorkflowSource {
        let id = WorkflowIdentity.normalizeIdentifier(workflow.identifier)
        guard let shipped = all.first(where: { $0.identifier == id }) else {
            return WorkflowSource(kind: .local, date: nil)
        }
        var source = WorkflowSource(kind: .builtin, date: nil)
        source.modified = !workflow.sameBehavior(as: shipped)
        return source
    }

    // AppPad's own workflows are trusted: allow what they declare once. Upgrades may add a new
    // permission (e.g. a different built-in action); answers the user already gave are kept.
    private static func grantUndecided(_ identifier: String, in store: WorkflowStore) {
        guard let installed = store.workflow(identifier: identifier) else { return }
        let undecided = installed.requiredPermissions.filter {
            PermissionStore.shared.decision(for: $0, workflow: installed.id) == nil
        }
        guard !undecided.isEmpty else { return }
        PermissionStore.shared.set(.allow, for: undecided, workflow: installed.id)
    }

    // MARK: - Groups

    static func groupTitle(_ group: String) -> String {
        group == Self.group ? String(localized: "System") : group
    }

    // MARK: - Clock shortcuts

    // Shown when the shortcut a built-in workflow calls is missing (nil for other shortcuts).
    static func setupText(for shortcut: String) -> String? {
        guard shortcut == clockShortcut else { return nil }
        if bundledShortcut(shortcut) != nil {
            return String(localized: "Timers and alarms use the “AppPad Clock” shortcut. Press ↩ to add it once; after that it runs in the background.")
        }
        return String(localized: "Timers and alarms need the “AppPad Clock” shortcut, which is not included in this build.")
    }

    // A signed .shortcut file shipped in the app bundle, if any (opening it imports the shortcut).
    static func bundledShortcut(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "shortcut")
    }

    // MARK: - Helpers

    private static func make(_ identifier: String, _ name: String, _ summary: String, version: String = "1.0",
                             keywords: [String], symbol: String, notice: SuccessNotice = .none, copy: Bool = false,
                             confirm: Bool = false,
                             argument: ArgumentMode = .off, type: ArgumentType = .text, hint: String = "",
                             steps: [WorkflowStep]) -> Workflow {
        var w = Workflow(name: name, identifier: identifier, steps: steps)
        w.version = version
        w.summary = summary
        w.group = group
        w.keywords = keywords
        w.symbol = symbol
        w.successNotice = notice
        w.copyOutput = copy
        w.requiresConfirmation = confirm
        w.argument = argument
        w.argumentType = type
        w.argumentHint = hint
        w.localizations = WorkflowLanguage.translations(of: name, summary: summary, hint: hint,
                                                        keywords: keywords.joined(separator: ", "))
        return w
    }

    private static func shortcutStep(_ name: String, input: String) -> WorkflowStep {
        var step = WorkflowStep(kind: .shortcut)
        step.shortcutName = name
        step.shortcutInput = input
        step.timeout = 30
        return step
    }

    private static func openURLStep(_ template: String) -> WorkflowStep {
        var step = WorkflowStep(builtin: .openURL, timeout: 10)
        step.url = template
        return step
    }
}
