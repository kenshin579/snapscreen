import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class TextRecognizerTests: XCTestCase {
    func testJoinedTextEmpty() {
        XCTAssertEqual(TextRecognizer.joinedText([]), "")
    }

    func testJoinedTextSingle() {
        XCTAssertEqual(TextRecognizer.joinedText([(text: "hello", minY: 0.5)]), "hello")
    }

    func testJoinedTextTopToBottomByMinY() {
        let lines = [(text: "bottom", minY: 0.1),
                     (text: "top", minY: 0.9),
                     (text: "middle", minY: 0.5)]
        XCTAssertEqual(TextRecognizer.joinedText(lines), "top\nmiddle\nbottom")
    }
}
