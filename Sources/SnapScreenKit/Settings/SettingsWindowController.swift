import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let policyManager: ActivationPolicyManager?

    public init(settings: SettingsStore, updateState: UpdateState,
                policyManager: ActivationPolicyManager? = nil) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: SettingsView(settings: settings,
                                                                 updateState: updateState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen 설정"
        // 인라인 타이틀바 — 트래픽 라이트가 사이드바 위에 얹힌다 (System Settings 스타일)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        guard let window else { return }
        policyManager?.register(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if let window { policyManager?.unregister(window) }
    }
}
