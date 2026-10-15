import AppKit

// Main menu: never shown (agent app), but its key equivalents still work:
// Edit items keep ⌘C/⌘V/⌘A working in text fields, ⌘, / ⌘Q in Settings.
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(localized: "Settings…"),
            action: #selector(AppDelegate.openSettingsFromMenu(_:)),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())
        // Enabled only while Settings is open (see AppDelegate.validateMenuItem).
        appMenu.addItem(
            withTitle: String(localized: "Quit AppPad"),
            action: #selector(AppDelegate.quitFromMenu(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        return main
    }
}
