# Changelog

<p align="center">
  English ·
  <a href="docs/i18n/CHANGELOG.zh-CN.md">简体中文</a> ·
  <a href="docs/i18n/CHANGELOG.zh-TW.md">繁體中文</a> ·
  <a href="docs/i18n/CHANGELOG.ja.md">日本語</a> ·
  <a href="docs/i18n/CHANGELOG.ko.md">한국어</a> ·
  <a href="docs/i18n/CHANGELOG.de.md">Deutsch</a> ·
  <a href="docs/i18n/CHANGELOG.es.md">Español</a> ·
  <a href="docs/i18n/CHANGELOG.fr.md">Français</a> ·
  <a href="docs/i18n/CHANGELOG.it.md">Italiano</a> ·
  <a href="docs/i18n/CHANGELOG.nl.md">Nederlands</a>
</p>

All notable changes to AppPad are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Each release section starts with `## vX.Y.Z` — `push_apppad_release.sh` uses it as the GitHub release notes.


## v1.3.5

### Added

#### Launchpad
- Optional keyboard shortcut to open Launchpad (⌥Space by default, off by default): press it again to close. Turn it on and change it in Settings › AppPad › Open with Shortcut; when on, it also appears in the menu bar menu.

#### Welcome Guide
- The pinch page now lets you turn on the Launchpad shortcut and pick a hot corner for Launchpad.

### Changed
- Backup: App shortcut backups now include the Launchpad shortcut.

## v1.3.4

### Added

#### Launchpad
- Fast page swiping (Settings › General, off by default): a short two-finger swipe turns a page, and one swipe can move several pages. Up/down swipes follow your fingers the same way.
- With fast page swiping on, press and drag the page dots to scroll the pages continuously; release to settle on the nearest page. Also works inside folders.

### Changed
- Launchpad: You can pick up the next icon while the previous one is still flying into place (e.g. into a folder) — no need to wait for the animation to finish.

## v1.3.3

### Added

#### Hot Corners
- New hot corners in Settings › AppPad: each screen corner can open AppPad, Workflows or Clipboard, or run a macOS action (Mission Control, Application Windows, Desktop, Notification Center, Quick Note, screen saver, display sleep, Lock Screen).
- Hold ⌘, ⌥, ⌃ or ⇧ (or a combination) while choosing an action to make that corner work only while those keys are held, just like macOS.

### Note
- Notification Center and Quick Note need Accessibility permission.
- If a corner is also set in the macOS hot corners, both run; AppPad shows a warning with a shortcut to System Settings.

## v1.3.2

### Added

#### Workflows
- New built-in action "Pre-fill Terminal Command": opens Terminal in a chosen folder with a command typed at the prompt. Nothing runs until you press Return. `{{input}}` is replaced by the argument.

### Changed
- Workflows: Install Homebrew now pre-fills the official install command in Terminal; press Return to start it.
- Workflows: before a script controls another app, AppPad asks macOS for permission first, so the app appears in Privacy & Security › Automation. If access is denied, the workflow stops with a clear message.
- AI Assistants: AI can write workflows that pre-fill Terminal commands; installing Homebrew through AI also only pre-fills the command.

### Note
- If Terminal asks to terminate a running process when you close the window, add `zsh` to the processes it ignores in Terminal's settings (Profiles › Shell › Ask before closing).

## v1.3.1

### Added

#### Workflows
- New built-in workflow “App Store Search”: type `mas` or `appstore` followed by keywords to open the results directly in the App Store.

### Fixed
- Workflow Panel: ⌘1–⌘0 on a workflow that takes an argument now selects it and fills in its name, ready for the argument, instead of doing nothing.

## v1.3.0

### Fixed
- Clipboard: Calculator results copied in AppPad now show the AppPad icon as the source app instead of an empty placeholder.

## v1.2.9

### Added

#### Workflows
- Every workflow shows where it came from: Built-in (green), Mine (blue, written by you or saved by an AI assistant) or third-party (orange, with the website it came from or "Imported File").
- The Workflow panel marks third-party rows with an orange icon; the preview shows the full link and when it was imported.
- Permission prompts show the workflow's source; run confirmations show it for third-party workflows.

### Changed
- Workflows: Changing the steps or permissions of a built-in or third-party workflow marks it "Edited"; a third-party workflow stays third-party after editing.
- Workflows: When a workflow is replaced by one from a different source, AppPad asks for its permissions again.

### Fixed
- Workflows: Imported workflows could replace built-in ones by reusing their ID; they are now skipped.
- Backup: Restoring no longer overwrites built-in workflows; only their on/off state and panel shortcut are restored.

### Note
- Non-built-in workflows added before this version show as "Mine", because their source was not recorded.

## v1.2.8

### Added

#### AI Assistants
- AI assistants can search, install and uninstall apps with Homebrew. Only apps from Homebrew’s official catalog that are notarized by Apple are installed (command-line tools only from inside the app), and each app is checked again after installing.
- Every install and uninstall asks for your confirmation first. You can turn this off in Settings › AI Assistants; a warning then lists the risks.
- If Homebrew is missing, AppPad offers to open Terminal with Homebrew’s official install command.

#### Workflows
- New built-in workflow “Install Homebrew”.

### Changed
- AI Assistants: Confirmations triggered by AI (installing, uninstalling, saving workflows, running, permissions) now appear in front without bringing AppPad’s other windows forward.

### Note
- Apps uninstalled with Homebrew are deleted right away, not moved to the Trash.
- Formulae and third-party taps are not supported. Homebrew is only detected in /opt/homebrew and /usr/local.

## v1.2.7

### Added

#### Menu Bar
- "Check for Updates…" now has the ⌘U shortcut.

### Fixed
- Menu Bar: Global shortcuts (Workflows, Clipboard, app and window shortcuts) pressed while the menu is open now close it and run right away, instead of waiting until the menu is dismissed.
- Menu Bar: Opening Settings with ⌘, from the menu while Workflows or Clipboard is open no longer briefly turns the panel background transparent.

## v1.2.6

### Fixed
- Launchpad: Changing the number of grid rows or columns no longer rearranges all pages. When the grid gets larger, only pages that were full take icons from the start of the next page, and pages that weren't full stay as they are; when it gets smaller, icons that no longer fit move to the start of the next page.

## v1.2.5

### Changed
- Launchpad: Apps still downloading from the App Store now show their icon at 70% opacity, so they are easier to recognize.

### Fixed
- Launchpad: When an App Store download finished, a blank dashed tile briefly appeared before the app's icon. The icon now switches over directly.
- Launchpad: Apps just installed with Homebrew or dragged into Applications no longer show the generic app icon first.

## v1.2.4

### Added

#### AI Assistants (MCP)
- One-click Claude Desktop setup: “Add to Claude Desktop” and “Remove from Claude Desktop” buttons with a live status (Added / Not added / Not installed). Only AppPad’s own entry in claude_desktop_config.json changes; your other MCP servers stay as they are.
- If AppPad has moved since it was added, the status says so and “Add to Claude Desktop” updates the path.

#### Workflows
- New built-in workflows “Add AppPad to Claude Desktop” and “Remove AppPad from Claude Desktop”. Type “claude” or “mcp” in the Workflow panel to find them.

#### Welcome Guide
- The AI page now has the same Add / Remove buttons for Claude Desktop.

### Note
- Restart Claude Desktop after adding or removing AppPad for the change to take effect.
- If Claude Desktop is not installed, nothing is added and AppPad tells you so.
- Before every change, a backup of the previous file is saved next to it as claude_desktop_config.json.apppad-backup.

## v1.2.3

### Fixed
- Clipboard: Saved items are now sorted by most recent use, just like the history. An item moves to the top after you paste or copy it, instead of staying in the order it was saved.

## v1.2.2

### Changed
- Workflow panel: "Last Run" in the preview now shows a status icon in the same style as the argument check, one shade lighter: green ✓ for succeeded, red ✕ for failed, gray – for cancelled, with matching text color, so the last result is clear at a glance.
- Workflow panel: A cancelled run is no longer shown in red like a failure.

## v1.2.1

### Changed
- Launchpad: Improved drag-and-drop between apps and folders.

### Fixed
- Settings: Fixed an issue where the Settings window overlapped other windows when opened.

## v1.2.0

### Changed
- Launchpad: Clicking an app now closes Launchpad with the same zoom-and-fade animation as clicking empty space, instead of disappearing instantly.

## v1.1.9

### Added
- Launchpad: app icons now show the same red badges as the Dock (unread counts, updates). Folders show the total of the apps inside, or a red dot when the apps inside only have text badges.
- Settings › General: new "Show app badges" switch, on by default. Badges are read from the Dock and need Accessibility permission; without it, the switch shows a hint with a button to open System Settings.

## v1.1.8

### Changed
- Appearance: refined button shapes and toggle switch colors.
- Shortcuts: improved the performance of the shortcut list.
- Saved Clips: changed how duplicate clipboard items are handled.

### Fixed
- Fixed an issue with setting the left-side width.

## v1.1.7

### Changed
- Appearance: all toggles are now green, and all buttons share the same pill shape.
- Uninstall: refined the delete confirmation page.

## v1.1.6

### Added

#### Welcome Guide
- On first launch AppPad now opens a welcome guide instead of Launchpad: a short tour of the features, followed by a few setup steps. Every step can be skipped, and Esc or ⌘W closes the guide.
- Four-finger pinch: turn it on or off, see which macOS gestures to turn off and in which order, and open Trackpad settings with one click.
- Clipboard: turn the history on or off, see its shortcuts and the most useful keys (⌘1–⌘0, ⌘S, ⌘↩), and how clicking an app's icon shows only what was copied from that app.
- ⌘Space for Workflows: turn off Spotlight's shortcut with one click. The change takes effect right away, without logging out, and can be undone on the same page. If it can't be changed automatically, the guide points to Keyboard settings.
- App Shortcuts: try it by giving Safari ⌃⌘J with one click, then add more in Settings › App Shortcuts.
- AI writes workflows: turn on AI Assistants (MCP), copy the setup for Claude Code or other clients, and try example prompts. Every workflow the AI writes still needs your approval.
- Permissions and startup: grant Accessibility (needed for pasting and window control) and turn on launch at login, with a live status for each.
- The last page lists the shortcuts for Launchpad, Clipboard, Saved items and Workflows; "Open AppPad" goes straight to Launchpad.
- Swipe left or right with two fingers, or click or drag along the dots at the bottom, to move between pages.
- Reopen the guide at any time from Settings › About › Show Welcome Guide….

### Changed
- The welcome guide replaces the separate one-time pinch and Spotlight hints. If you already saw those hints, the guide doesn't open by itself.
- Automatic updates wait until the welcome guide is closed.

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
