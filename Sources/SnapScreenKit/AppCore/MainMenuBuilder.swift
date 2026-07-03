import AppKit

@MainActor
public enum MainMenuBuilder {
    public static func install() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "SnapScreen 종료",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: "SnapScreen"))

        let fileMenu = NSMenu(title: "파일")
        fileMenu.addItem(withTitle: "저장…", action: Selector(("saveImage:")), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(fileMenu, title: "파일"))

        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undoAction:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "실행 복귀", action: Selector(("redoAction:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "복사", action: Selector(("copyMerged:")), keyEquivalent: "c")
        main.addItem(submenu(editMenu, title: "편집"))

        NSApp.mainMenu = main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
