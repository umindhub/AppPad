<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  The original Launchpad, back on macOS 26+ — plus clipboard, workflows, app shortcuts and window control.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Website</a> ·
  English · <a href="README.zh-CN.md">简体中文</a>
</p>

---

## Features

### Launchpad
- Faithful recreation of the classic macOS Launchpad, default layout follows the system order
- Open by four-finger pinch, menu bar, or clicking AppPad in the Dock (click again to close)
- Folders, drag to reorder / create folders, long-press or hold ⌥ for edit mode
- Built-in clean uninstall: removes the app together with its leftover files
- Grid search, page indicator (dots / numbers), Liquid Glass controls
- Backgrounds: wallpaper / white / light gray / dark gray / custom color, separate settings for light & dark theme

### Clipboard
- Permanent history of text and images (images survive deletion of the original file)
- Saved library for frequently used items, `⌘1`–`⌘0` to paste
- Source-app filter chips and `AppName::` search syntax, live preview

### Workflows
- `⌘Space` opens the Workflow panel: apps and workflows ranked together by frecency
- Workflows run Apple Shortcuts, AppleScript or shell scripts, with arguments (e.g. `time 10`)
- Built-in: Empty Trash, Set Timer, Set Alarm, Set Volume, Quit All Apps, calculator…
- Declared permissions enforced by a real sandbox (Allow Once / Don't Allow / Always Allow)
- Import / share workflows as JSON files or links

### App Shortcuts
- Global hotkey for any app, Raycast-style

### Window Control
- Snap left / right (½ → ⅓ → ⅔), maximize, restore, move to another display — all hotkeys customizable

### Other
- Menu-bar only (no Dock icon), launch at login
- `⌘⇧J` / `⌘⇧K` morphs between Launchpad, Clipboard and Workflows
- 10 languages: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Requirements

- macOS 26 or later
- Xcode 27 (to build from source)

## Build

1. Open `AppPad.xcodeproj`
2. Select a scheme: `AppPad Dev`, `AppPad Beta` or `AppPad`
3. Set your own signing team, then build & run

Dependencies are resolved by Swift Package Manager.

## License

AppPad uses a split license:

| Part | License |
| --- | --- |
| AppPad application source code (everything not listed below) | [AGPL-3.0](LICENSE) |
| Built-in workflows (`AppPad/Workflow/BuiltinWorkflows.swift`, `*.shortcut`) | [MIT](LICENSE-MIT) |
| Workflow format specification | [MIT](LICENSE-MIT) |
| Third-party workflows in the Workflow Market | [MIT](LICENSE-MIT), © their authors |

- **AGPL-3.0**: you may use, modify and redistribute AppPad, but any distributed or network-served derivative must be released under AGPL-3.0 with full source code.
- **Commercial license**: for closed-source or proprietary use, contact the author via the [website](https://apppad.youmindhub.com) for a commercial license.
- **MIT for workflows**: anyone can freely write, share or sell workflows, and implement the workflow format in other tools, without AGPL obligations.
- Workflows you create are yours. Workflows submitted to the Workflow Market must be MIT-licensed.
- The name "AppPad" and its icon are not covered by these licenses; forks must use a different name and icon.

## Contributing

Issues and pull requests are welcome. By submitting a contribution you agree that it is licensed under the license of the part you change, and you grant the maintainer the right to also distribute your contribution under the commercial license.

## Acknowledgements

- [GRDB.swift](https://github.com/groue/GRDB.swift) — MIT License

---

© 2026 YouMindHub
