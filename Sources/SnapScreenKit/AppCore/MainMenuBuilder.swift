import AppKit

@MainActor
public enum MainMenuBuilder {
    public static func install() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L("Settings…"), action: Selector(("openSettings:")), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L("Quit SnapScreen"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: "SnapScreen"))

        let fileMenu = NSMenu(title: L("File"))
        fileMenu.addItem(withTitle: L("Save…"), action: Selector(("saveImage:")), keyEquivalent: "s")
        fileMenu.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(fileMenu, title: L("File")))

        let editMenu = NSMenu(title: L("Edit"))
        editMenu.addItem(withTitle: L("Undo"), action: Selector(("undoAction:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: L("Redo"), action: Selector(("redoAction:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: L("Copy"), action: Selector(("copyMerged:")), keyEquivalent: "c")
        main.addItem(submenu(editMenu, title: L("Edit")))

        NSApp.mainMenu = main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
