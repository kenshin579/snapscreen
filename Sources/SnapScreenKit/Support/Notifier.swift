import AppKit
import Foundation
import UserNotifications

public enum Notifier {
    public static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { _, _ in }
    }

    public static func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 알림 권한이 없어도 반드시 사용자에게 들리는 하드 실패 알림 (beep + 알림 시도)
    public static func alertFailure(title: String, body: String) {
        NSSound.beep()
        show(title: title, body: body)
    }
}
