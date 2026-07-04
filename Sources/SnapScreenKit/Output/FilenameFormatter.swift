import Foundation

/// 스크린샷 저장 파일명을 생성한다. (예: "snapscreen 2026-07-03 14.30.15.png")
public struct FilenameFormatter {
    private let prefix: String
    private let formatter: DateFormatter

    public init(prefix: String = "snapscreen", timeZone: TimeZone = .current) {
        self.prefix = prefix
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    }

    public func filename(for date: Date) -> String {
        "\(prefix) \(formatter.string(from: date)).png"
    }
}
