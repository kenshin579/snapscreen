import XCTest
import AppKit
@testable import SnapScreenKit

final class ClipboardWriterTests: XCTestCase {
    func testWriteTextRoundTrips() {
        ClipboardWriter.write(text: "안녕 hello 123")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "안녕 hello 123")
    }

    func testWriteTextReplacesPrevious() {
        ClipboardWriter.write(text: "first")
        ClipboardWriter.write(text: "second")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "second")
    }
}
