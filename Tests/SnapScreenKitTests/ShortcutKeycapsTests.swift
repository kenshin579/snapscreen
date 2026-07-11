import XCTest
@testable import SnapScreenKit

final class ShortcutKeycapsTests: XCTestCase {
    func testModifiersAndKeySplitIntoIndividualKeycaps() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "⌘⇧1"), ["⌘", "⇧", "1"])
    }

    func testSingleModifierWithLetter() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "⌘A"), ["⌘", "A"])
    }

    func testNoModifierSingleKey() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "F2"), ["F", "2"])
    }

    func testEmptyStringReturnsEmptyArray() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: ""), [])
    }

    func testCombiningKeycapStaysSingleElement() {
        // 키패드 1 = "1" + U+20E3(결합 enclosing keycap) → 하나의 grapheme cluster
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "⌘1\u{20E3}"), ["⌘", "1\u{20E3}"])
    }
}
