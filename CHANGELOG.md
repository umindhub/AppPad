# Changelog

All notable changes to AppPad are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Each release section starts with `## vX.Y.Z` — `push_apppad_release.sh` uses it as the GitHub release notes.

## v1.1.5

### Changed
- Launchpad: click a folder's name to rename it at any time, not only in edit mode.

### Fixed
- Launchpad: a folder's name no longer shifts to the left after renaming it with ↩.

## v1.1.4

### Fixed
- Fixed: newly installed apps (e.g. via Homebrew) could show a blank icon until AppPad was restarted.

## v1.1.3

### Added
- Launchpad: apps downloading from the App Store show up right away, dimmed with a progress bar, and become normal once installed.
- Launchpad: deleting an app shows a progress bar under its icon; the icon disappears when it's done.

### Changed
- Uninstall: app settings and data in the sandbox containers are kept, as when deleting from Finder, so reinstalling restores them.

### Fixed
- Uninstall: App Store apps and other apps owned by the system can be deleted again (Finder asks for your password or Touch ID). Leftovers in `/Library` are removed the same way.
- Uninstall: widgets and extensions still running from the app no longer block deleting it.

## v1.1.2

### Changed
- Launchpad: opening and closing a folder by clicking is now more reliable.

## v1.1.1

### Changed
- Updates: the update prompt now counts down and closes itself when time runs out.

## v1.1.0

### Changed
- Launchpad: opening and closing a folder is now smoother and more responsive, with less work done per frame during the animation.

## v1.0.9

### Added

#### Launchpad
- Search now finds folders by name, including pinyin and initials, just like apps.
- Search for several things at once with `|` or `||`, e.g. `WeChat | Social` shows the app and the folder together, so you can drop the app straight into the folder.

### Changed
- AppPad now supports macOS 15 Sequoia and later (previously macOS 26 Tahoe or later). Liquid Glass controls remain available on macOS 26 and later.

## v1.0.8

### Added

#### Launchpad
- Uninstalling an app that was installed with Homebrew (`brew install --cask`) now also removes it from Homebrew: after the app and its leftovers are in the Trash, AppPad runs `brew uninstall --cask` for its cask. Without Homebrew, or for apps that aren't a cask, nothing changes.
- If Homebrew can't finish on its own (for example when the cask needs an administrator password), AppPad shows the command to run in Terminal, with a button to copy it.

#### Workflows
- In the Workflow panel, the result of a typed argument now starts with a green checkmark when it is valid and a red cross when it isn't.

### Changed
- Switching from Launchpad to the Clipboard or Workflow panel: the panel's shadow now fades in during the morph instead of appearing after it.
- Panel shadows are drawn by AppPad and stay outside the panel. With a translucent background, the Clipboard and Workflow panels now look exactly like Launchpad, with the same blur and transparency and no extra darkening.
- Workflow panel: a valid argument result is shown in the normal text color instead of green; an invalid one stays red.
- Choosing Launchpad, Clipboard or Workflows in the menu-bar menu while another panel is open now switches the same way as ⌘⇧J / ⌘⇧K.

### Fixed
- Switching between the Clipboard and Workflow panels with ⌘⇧J / ⌘⇧K could flash for a moment.
- Opening a panel from the menu bar while another one was open briefly showed the desktop.

## v1.0.7

### Added

#### AI Assistants (MCP)
- Claude, Cursor and other MCP clients can list and run your workflows, passing an argument just like the Workflow panel. Results come back to the AI instead of as notifications.
- AI assistants can also write workflows for you. Every new or changed workflow is shown in full, scripts included, and only saved after you click Install.
- Runs use the same confirmations and permission prompts as the Workflow panel. Disabled workflows stay hidden.
- New AI Assistants (MCP) tab in Settings, below Workflows: on by default, shows the connection status and has copy-ready setup for Claude Desktop, Cursor and Claude Code.
- If AppPad isn't running, the AI client starts it in the background without opening Launchpad.

## v1.0.6

### Added

#### Launchpad
- Search keeps folders: an app inside a folder now shows up as its folder. Open it with a click or ↩; the matching app is highlighted, and ↩ again opens it.
- Search results can be dragged: drag an app out of the panel onto the Dock or into Finder.
- Create folders while searching: drop an app slowly onto another result to make a new folder, or onto a folder to add it. Apps dragged out of a folder opened from the results can be dropped the same way. Hold at the side of the panel to flip to the next or previous results page.

### Changed
- When a folder is left with a single app, that app now slowly grows out of the folder instead of popping in.
- While searching, the open folder, the results page and the selection are kept when the layout changes (reordering inside a folder, renaming, uninstalling), and results keep their order after a merge instead of being re-ranked.

### Fixed
- Clicking during a drop animation (for example on a folder that is still forming) could close Launchpad.

## v1.0.5

### Added

#### Automatic Updates
- AppPad now keeps itself up to date. Every day at 4:00 it checks for a new version, downloads it in the background and installs it as soon as no panel is open, then restarts quietly without opening Launchpad.
- Missed the check because the Mac was asleep or off? AppPad catches up shortly after waking, and retries every 30 minutes if the network isn't ready.
- New Updates section in Settings › About: turn automatic updates on or off (on by default), pick the check time, see when the last check ran, and check now.
- "Check for Updates…" in the menu-bar menu.
- If an update is waiting while you're in Settings, "Restart to Update" installs it right away.
- Updates are verified with an EdDSA signature before they are installed.

### Changed
- Settings › About lists Sparkle under Acknowledgements.

### Note
- Versions before 1.0.5 can't update themselves: install 1.0.5 once from the DMG or with `brew upgrade --cask apppad`; later versions arrive automatically.

## v1.0.4

### Added
- Saved Clips: the content of text items can now be edited as well as their name. Click the text to open the editor; ⌘↩ saves, Esc cancels. An edit that would duplicate another item is refused.

### Changed
- Saved Clips: the Copy button briefly turns into a green checkmark after a successful copy; the row keeps its height.

### Fixed
- Saved Clips: copying an item no longer changes its source app to AppPad. The copy now counts as a use, like pasting from the Clipboard panel, and moves the item to the top of the history.

## v1.0.3

### Added

#### Clipboard
- New "Saved Clips" tab in Settings to browse, search and manage the saved library: source app icon, name, two-line preview and date for every item, with Copy and Remove buttons.
- Saved items can have a name. Names are searchable both in Settings and in the Clipboard panel, and named items show their name in bold in the list.
- ⌘↩ on any clipboard item opens it in Settings › Saved Clips with the name field ready to type; unsaved items are saved first. Also available from the context menu ("Edit in Saved Clips").

#### Backup & Restore
- Backups now include item names. Older backups restore as before; when merging, a name already set on this Mac is kept.

### Changed
- Clipboard: delete an item with ⌘⇧⌫ (was ⌘⌫), so ⌘⌫ in the search field deletes to the start of the line again.
- Clipboard: "Show in Finder" moved from ⌘↩ to ⌘⇧↩.

## v1.0.2

### Added

#### Workflows
- New "Ask before running" option in the workflow editor: a confirmation appears before the workflow runs, whether it is started from the Workflow panel or from Settings.
- In the Workflow panel the confirmation opens inside the panel: ↩ runs, Esc cancels, other keys are ignored. A held or quickly repeated ↩ never confirms.
- The workflow format gains an optional `"confirm": true` field; existing files without it run as before.

### Changed
- The built-in "Quit All Apps" workflow (v1.4) now asks for confirmation, so Tab or ↩ in the Workflow panel can no longer quit every app by accident.

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
