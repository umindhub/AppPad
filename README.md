<p align="center">
  <img src="docs/images/icon.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Brings the original Launchpad back to macOS 26+ (runs on macOS 15 too) — plus clipboard, workflows, app shortcuts and window control.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Website</a> · <a href="CHANGELOG.md">Changelog</a>
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
- `⌘⇧K` / `⌘⇧J` morphs between Launchpad, Workflows and Clipboard
- 10 languages: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Requirements

- macOS 15 or later

## License

AppPad is proprietary commercial software. © 2026 YouMindHub. All rights reserved. This repository hosts release builds and documentation only; the source code is not public.

| Part | License |
| --- | --- |
| AppPad application | Proprietary, all rights reserved |
| Built-in workflows | Part of AppPad, proprietary, all rights reserved |
| Workflow format specification | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), © YouMindHub |
| Third-party workflows in the Workflow Market | © their authors, licensed on terms chosen by each author |

- Workflows you create are yours. You decide how to license, share or sell them.
- By submitting a workflow to the Workflow Market, you grant YouMindHub a non-exclusive right to host and distribute it through AppPad. Copyright stays with you.
- The workflow format specification is licensed under CC BY 4.0: you may copy, adapt and redistribute it as long as you credit AppPad.
- Built-in workflows may not be extracted or redistributed separately from AppPad.
- The name "AppPad" and its icon are not covered by any of the licenses above.

## Acknowledgements

- [GRDB.swift](https://github.com/groue/GRDB.swift) — MIT License
- [Sparkle](https://github.com/sparkle-project/Sparkle) — MIT License

---

© 2026 YouMindHub
