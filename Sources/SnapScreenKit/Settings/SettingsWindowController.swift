import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public init(settings: SettingsStore) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
