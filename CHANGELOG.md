# Changelog

All notable changes to AppPad are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Each release section starts with `## vX.Y.Z` — `push_apppad_release.sh` uses it as the GitHub release notes.

## v1.0.1

### Added

#### Backup & Restore
- New Backup tab in Settings: export to a single `.apppadbackup` file and restore it on this or another Mac.
- Choose what to include: app shortcuts (plus the Workflows, Clipboard and window shortcuts), the Launchpad layout with its grid size, installed workflows (with icons, panel shortcuts and on/off state), clipboard history and the saved library.
- Restore shows what a backup contains before anything changes; pick the parts to restore and whether to merge with or replace what's already there.
- Merge adds what is missing: newer workflow versions replace older ones, and clipboard items are matched by content, so nothing is duplicated.
- The Launchpad layout is always replaced; apps not installed on this Mac are skipped, and apps not in the backup are added at the end.
- Keychain secrets and "Always Allow" permissions are never written to a backup; restored workflows ask for permission again on their first run.

## v1.0.0

First public release. Requires macOS 26 Tahoe or later (Universal: Apple Silicon + Intel).

### Added

#### Launchpad
- The classic Launchpad is back on macOS 26+, with the familiar default layout (less-used system apps grouped in an "Other" folder).
- Open with a four-finger pinch, the menu bar, or by clicking AppPad in the Dock (click again to close). A click cancels the pinch animation at any time.
- Two-finger swipe paging; page indicator as dots or numbers, tappable and drag-scrubbable with a Liquid Glass lens.
- Instant search, just like Launchpad on macOS 15; results ranked by how often and how recently you use each app.
- Edit mode by long-pressing an app icon or holding ⌥ Option: drag to reorder, drop apps onto each other to create folders. Folders can span multiple pages.
- Built-in clean uninstall: delete an app from edit mode and AppPad also removes its leftover files.
- Window size follows the screen with separate width and height percentages; at full size it can cover the menu bar and stays clear of the notch.
- Opens on the display under the mouse (optional) and stays on the Space it was opened on, like the original Launchpad.

#### Clipboard
- Clipboard history for text and images, kept permanently; images survive even if the original file is deleted.
- Saved library for frequently used items — toggle "Saved" next to the search field; saved items rank first in search.
- Open with ⌘. (saved library: ⌘⌥.), paste with ⌘1–⌘0, preview pane on the right.
- Source app icon on every item, filter chips for your top apps, and `AppName::` search syntax.
- ⌘↩ reveals an image's source folder in Finder.
- Clean up history by age (last hour, day, week … over a year) without touching the saved library.

#### Workflows
- Workflow panel (⌘Space) that runs Apple Shortcuts, AppleScript and shell scripts, and launches apps from the same search.
- Arguments: type after the first space, e.g. `Set-Timer 10:00`. Tab completes the selected item.
- Built-in workflows: Empty Trash, Set Timer, Set Alarm, Set Volume, Mute, Quit All Apps, and a calculator with scientific notation.
- Permission system with a real sandbox for shell and AppleScript workflows: Allow Once / Don't Allow / Always Allow.
- Import workflows from JSON files or links, with unique ids, revisions and multi-language names.
- Per-workflow success and failure notifications.
- Apps and workflows share one frecency ranking.

#### Window Control
- ⌃⌥← / ⌃⌥→ snap left / right, cycling ½ → ⅓ → ⅔.
- ⌃⌥↩ maximize, ⌃⌥⌫ restore, ⌃⌥⌘↑ / ⌃⌥⌘↓ move to the previous / next display.
- All shortcuts are customizable.

#### App Shortcuts
- Global hotkeys to open any app, with an A–Z app list and conflict detection.

#### Appearance & General
- Liquid Glass search field, page indicator and settings tabs.
- Theme: Auto / Light / Dark.
- Backgrounds: white, light gray, dark gray, wallpaper or custom color, each with its own transparency and blur for light and dark themes. Clipboard and Workflow panels can follow the Launchpad background.
- ⌘⇧J / ⌘⇧K switch between Launchpad, Clipboard and Workflows with a smooth morph animation.
- Menu-bar only (no Dock icon unless you pin it), launch at login.
- Optional switch to the ABC input source when each panel opens.
- Configurable Esc behavior (close immediately, or clear the search first).
- Localized in 10 languages: English, Deutsch, Español, Français, Italiano, 日本語, 한국어, Nederlands, 简体中文, 繁體中文.

#### Distribution
- Signed with Developer ID and notarized by Apple.
- Install with Homebrew: `brew tap umindhub/tap && brew trust umindhub/tap && brew install --cask apppad`.
- Source code under AGPL-3.0. Built-in workflows, the workflow format and third-party workflows under MIT.
