import XCTest
@testable import SnapScreenKit

final class FileSaverTests: XCTestCase {
    func testSanitizedPrefix() {
        XCTAssertEqual(FileSaver.sanitizedPrefix("shot"), "shot")
        XCTAssertEqual(FileSaver.sanitizedPrefix("a/b:c"), "a-b-c")
        XCTAssertEqual(FileSaver.sanitizedPrefix("   "), "snapscreen")
        XCTAssertEqual(FileSaver.sanitizedPrefix(""), "snapscreen")
    }

    func testUniqueURLAppendsCounter() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = FileSaver.uniqueURL(in: dir, filename: "shot.png")
        XCTAssertEqual(first.lastPathComponent, "shot.png")
        try Data().write(to: first)

        let second = FileSaver.uniqueURL(in: dir, filename: "shot.png")
        XCTAssertEqual(second.lastPathComponent, "shot (2).png")
        try Data().write(to: second)

        let third = FileSaver.uniqueURL(in: dir, filename: "shot.png")
        XCTAssertEqual(third.lastPathComponent, "shot (3).png")
    }
}
