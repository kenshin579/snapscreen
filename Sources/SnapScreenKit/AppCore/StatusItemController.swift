import AppKit

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: CaptureCoordinator
    private let openSettingsHandler: () -> Void

    public init(coordinator: CaptureCoordinator, openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.openSettingsHandler = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "SnapScreen")
        let menu = NSMenu()
        menu.addItem(item("영역 캡처", #selector(captureArea)))
        menu.addItem(item("창 캡처", #selector(captureWindow)))
        menu.addItem(item("전체 화면 캡처", #selector(captureFullScreen)))
        menu.addItem(.separator())
        menu.addItem(item("설정…", #selector(StatusItemController.openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("SnapScreen 종료", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func captureArea() { coordinator.beginCapture(.area) }
    @objc private func captureWindow() { coordinator.beginCapture(.window) }
    @objc private func captureFullScreen() { coordinator.beginCapture(.fullScreen) }
    @objc private func openSettings() { openSettingsHandler() }
    @objc private func quit() { NSApp.terminate(nil) }
}
