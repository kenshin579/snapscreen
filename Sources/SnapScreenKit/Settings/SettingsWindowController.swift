import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let policyManager: ActivationPolicyManager?
    private let uiState = SettingsUIState()

    public init(settings: SettingsStore, updateState: UpdateState,
                policyManager: ActivationPolicyManager? = nil) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: SettingsView(settings: settings,
                                                                 updateState: updateState,
                                                                 ui: uiState))
        let window = NSWindow(contentViewController: hosting)
        window.title = L("SnapScreen Settings")
        // 인라인 타이틀바 — 트래픽 라이트가 사이드바 위에 얹힌다 (System Settings 스타일)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    /// 설정 창 표시. section 지정 시 해당 섹션으로 전환해 연다
    /// (예: 메뉴바 "Update available…" → About 직행). nil이면 마지막 섹션 유지.
    func show(section: SettingsSection? = nil) {
        if let section { uiState.section = section }
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
