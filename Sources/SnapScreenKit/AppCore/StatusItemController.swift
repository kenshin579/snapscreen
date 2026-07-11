import AppKit
import Combine

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: CaptureCoordinator
    private let openHomeHandler: () -> Void
    private let openSettingsHandler: () -> Void
    private let updateState: UpdateState
    private var updateMenuItem: NSMenuItem?
    private var updateSeparator: NSMenuItem?
    private var phaseCancellable: AnyCancellable?

    public init(coordinator: CaptureCoordinator, updateState: UpdateState,
                openHome: @escaping () -> Void,
                openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.updateState = updateState
        self.openHomeHandler = openHome
        self.openSettingsHandler = openSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "SnapScreen")
        let menu = NSMenu()
        menu.addItem(item(L("SnapScreen Home…"), #selector(StatusItemController.openHome)))
        menu.addItem(.separator())
        menu.addItem(item(L("Area Capture"), #selector(captureArea)))
        menu.addItem(item(L("Window Capture"), #selector(captureWindow)))
        menu.addItem(item(L("Full Screen Capture"), #selector(captureFullScreen)))
        menu.addItem(.separator())
        menu.addItem(item(L("Settings…"), #selector(StatusItemController.openSettings)))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit SnapScreen"), #selector(quit)))
        statusItem.menu = menu

        phaseCancellable = updateState.$phase.sink { [weak self] phase in
            self?.refreshUpdateItem(for: phase)
        }
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// .available일 때만 메뉴 최상단에 "업데이트 가능 (vX.Y.Z)…" + 구분선을 노출한다
    private func refreshUpdateItem(for phase: UpdateState.Phase) {
        guard let menu = statusItem.menu else { return }
        if let item = updateMenuItem { menu.removeItem(item); updateMenuItem = nil }
        if let sep = updateSeparator { menu.removeItem(sep); updateSeparator = nil }

        guard case .available(let version, _) = phase else { return }
        let item = NSMenuItem(title: L("Update available (v\(version))…"),
                              action: #selector(StatusItemController.openSettings),
                              keyEquivalent: "")
        item.target = self
        let separator = NSMenuItem.separator()
        menu.insertItem(item, at: 0)
        menu.insertItem(separator, at: 1)
        updateMenuItem = item
        updateSeparator = separator
    }

    @objc private func captureArea() { coordinator.beginCapture(.area) }
    @objc private func captureWindow() { coordinator.beginCapture(.window) }
    @objc private func captureFullScreen() { coordinator.beginCapture(.fullScreen) }
    @objc private func openHome() { openHomeHandler() }
    @objc private func openSettings() { openSettingsHandler() }
    @objc private func quit() { NSApp.terminate(nil) }
}
