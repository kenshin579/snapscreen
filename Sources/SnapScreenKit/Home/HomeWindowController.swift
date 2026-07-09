import AppKit
import SwiftUI

/// 홈 창. 표시 시 ActivationPolicyManager에 등록(독 표시), 닫힐 때 해제(창 0개면 독 숨김).
@MainActor
public final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private let policyManager: ActivationPolicyManager

    public init(policyManager: ActivationPolicyManager,
                history: HistoryStore,
                onCapture: @escaping @MainActor (CaptureMode) -> Void,
                onOpenEntry: @escaping @MainActor (HistoryEntry) -> Void) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: HomeView(
            onCapture: onCapture, history: history, onOpenEntry: onOpenEntry))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen"
        window.styleMask = [.titled, .closable, .miniaturizable] // 리사이즈 불가
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        guard let window else { return }
        policyManager.register(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        policyManager.unregister(window)
    }
}
