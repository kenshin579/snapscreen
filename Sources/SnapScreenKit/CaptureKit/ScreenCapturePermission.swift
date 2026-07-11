import AppKit

@MainActor
public enum ScreenCapturePermission {
    /// 권한이 있으면 true. 없으면 시스템 요청을 트리거하고 안내 알림창을 띄운 뒤 false.
    public static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess() // 최초 1회만 시스템 프롬프트 발생

        let alert = NSAlert()
        alert.messageText = L("Screen Recording Permission Required")
        alert.informativeText = L("In System Settings > Privacy & Security > Screen & System Audio Recording, turn on SnapScreen, then relaunch the app.")
        alert.addButton(withTitle: L("Open System Settings"))
        alert.addButton(withTitle: L("Close"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
