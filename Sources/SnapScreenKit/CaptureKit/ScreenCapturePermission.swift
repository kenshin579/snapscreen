import AppKit

@MainActor
public enum ScreenCapturePermission {
    /// 권한이 있으면 true. 없으면 시스템 요청을 트리거하고 안내 알림창을 띄운 뒤 false.
    public static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess() // 최초 1회만 시스템 프롬프트 발생

        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요합니다"
        alert.informativeText = """
        시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 \
        SnapScreen을 켠 후, 앱을 다시 실행해 주세요.
        """
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "닫기")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
