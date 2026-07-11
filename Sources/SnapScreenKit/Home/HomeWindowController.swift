import AppKit
import SwiftUI

/// 홈 창. 표시 시 ActivationPolicyManager에 등록(독 표시), 닫힐 때 해제(창 0개면 독 숨김).
/// 인라인 투명 타이틀바: 트래픽 라이트는 시스템 것을 유지하고 타이틀바 배경은 본문(홈 그라디언트)에 녹인다.
@MainActor
public final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private let policyManager: ActivationPolicyManager

    public init(policyManager: ActivationPolicyManager,
                history: HistoryStore,
                onCapture: @escaping @MainActor (CaptureMode) -> Void,
                onOpenEntry: @escaping @MainActor (HistoryEntry) -> Void,
                onOpenSettings: @escaping @MainActor () -> Void) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: HomeView(
            onCapture: onCapture, history: history,
            onOpenEntry: onOpenEntry, onOpenSettings: onOpenSettings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen"
        // 리사이즈 불가 + 인라인 타이틀바(콘텐츠가 타이틀바 아래까지 확장)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
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
