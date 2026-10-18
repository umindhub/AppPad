<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Brings the original Launchpad back to macOS 26+ (runs on macOS 15 too) — plus clipboard, workflows, app shortcuts and window control.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Website</a><br>
  <a href="#wechat-donate">☕ Support via WeChat</a>
</p>

<p align="center">
  English ·
  <a href="docs/i18n/README.zh-CN.md">简体中文</a> ·
  <a href="docs/i18n/README.zh-TW.md">繁體中文</a> ·
  <a href="docs/i18n/README.ja.md">日本語</a> ·
  <a href="docs/i18n/README.ko.md">한국어</a> ·
  <a href="docs/i18n/README.de.md">Deutsch</a> ·
  <a href="docs/i18n/README.es.md">Español</a> ·
  <a href="docs/i18n/README.fr.md">Français</a> ·
  <a href="docs/i18n/README.it.md">Italiano</a> ·
  <a href="docs/i18n/README.nl.md">Nederlands</a>
</p>

---

## Installation

### Option 1: Download

[Download the latest release](https://github.com/umindhub/AppPad/releases/latest), open the DMG and drag AppPad into the Applications folder.

### Option 2: Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## Features

### Launchpad
- Faithful recreation of the classic macOS Launchpad, default layout follows the system order
- Open by four-finger pinch, menu bar, or clicking AppPad in the Dock (click again to close)
- Folders, drag to reorder / create folders, long-press or hold ⌥ for edit mode
- Built-in clean uninstall: removes the app together with its leftover files
- Grid search, page indicator (dots / numbers), Liquid Glass controls (macOS 26+)
- Backgrounds: white / light gray / dark gray / wallpaper / custom color, separate settings for light & dark theme

### Clipboard
- Text and images are kept permanently
- Any copied item can be saved
- `⌘1`–`⌘0` quick paste, source-app filter chips, `AppName::` search syntax, live preview

### Workflows & AI MCP
- `⌘Space` opens the Workflow panel: apps and workflows ranked together by frecency
- Workflows run shell scripts, AppleScript, Shortcuts or HTTP requests, with arguments (e.g. `time 10`)
- Built-in: Empty Trash, Set Timer, Set Alarm, Set Volume, Quit All Apps…
- Declared permissions enforced by a real sandbox (Allow Once / Don't Allow / Always Allow)
- Import / share workflows as JSON files or links
- Built-in MCP server: AI assistants that support MCP can call and control your workflows directly
- AI can read the workflow-writing rules through MCP and create new workflows for you
- Workflows run by AI go through the same permission prompts and sandbox as your own runs

### Calculator
- Type a math expression right in the Workflow panel search field to calculate (scientific notation supported)

### App Shortcuts
- Assign a global hotkey to any app

### Window Control
- Snap left / right (½ → ⅓ → ⅔), maximize, restore, move to another display — all hotkeys customizable

### Other
- Launch at login
- `⌘⇧J` / `⌘⇧K` morphs between Launchpad, Clipboard and Workflows
- 10 languages: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Requirements

- macOS 15 or later
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
- [Sparkle](https://github.com/sparkle-project/Sparkle) — MIT License

<a id="wechat-donate"></a>

## Support AppPad

AppPad is free and open source. If it makes your Mac a little nicer to use, you’re welcome to buy me a coffee via WeChat — any amount is appreciated, and a star on GitHub means a lot too. Thank you!

<p align="center">
  <img src="docs/images/wechat-donate.png" width="300" alt="WeChat">
  <br>
  <sub>Scan with WeChat</sub>
</p>

---

© 2026 YouMindHub
