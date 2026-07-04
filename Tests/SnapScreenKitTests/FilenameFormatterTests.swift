import XCTest
@testable import SnapScreenKit

final class FilenameFormatterTests: XCTestCase {
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, mo, d, h, mi, s)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal.date(from: c)!
    }

    func testDefaultPrefix() {
        let f = FilenameFormatter(timeZone: TimeZone(identifier: "Asia/Seoul")!)
        XCTAssertEqual(
            f.filename(for: date(2026, 7, 3, 14, 30, 15)),
            "snapscreen 2026-07-03 14.30.15.png"
        )
    }

    func testCustomPrefix() {
        let f = FilenameFormatter(prefix: "shot", timeZone: TimeZone(identifier: "Asia/Seoul")!)
        XCTAssertEqual(
            f.filename(for: date(2026, 1, 9, 9, 5, 7)),
            "shot 2026-01-09 09.05.07.png"
        )
    }
}
