import AppKit
import Combine

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: CaptureCoordinator
    private let openSettingsHandler: () -> Void
    private let updateState: UpdateState
    private var updateMenuItem: NSMenuItem?
    private var updateSeparator: NSMenuItem?
    private var phaseCancellable: AnyCancellable?

    public init(coordinator: CaptureCoordinator, updateState: UpdateState,
                openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.updateState = updateState
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
        let item = NSMenuItem(title: "업데이트 가능 (v\(version))…",
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
    @objc private func openSettings() { openSettingsHandler() }
    @objc private func quit() { NSApp.terminate(nil) }
}
