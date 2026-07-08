import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class PathEraserTests: XCTestCase {
    // 가로 일직선 점열 (y=0), x=0,10,20,...,100
    private let line = (0...10).map { CGPoint(x: CGFloat($0 * 10), y: 0) }

    func testNothingErasedReturnsOriginal() {
        let out = PathEraser.erase(line, along: [CGPoint(x: 50, y: 100)], radius: 5)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0], line)
    }

    func testMiddleEraseSplitsIntoTwo() {
        let out = PathEraser.erase(line, along: [CGPoint(x: 50, y: 0)], radius: 5)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(out[0].last, CGPoint(x: 40, y: 0))
        XCTAssertEqual(out[1].first, CGPoint(x: 60, y: 0))
        XCTAssertEqual(out[1].last, CGPoint(x: 100, y: 0))
    }

    func testEndEraseKeepsOneSegment() {
        let out = PathEraser.erase(line, along: [CGPoint(x: 100, y: 0)], radius: 5)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].last, CGPoint(x: 90, y: 0))
    }

    func testEraseAllReturnsEmpty() {
        let out = PathEraser.erase(line, along: [CGPoint(x: 50, y: 0)], radius: 1000)
        XCTAssertEqual(out.count, 0)
    }

    func testSinglePointSegmentsDropped() {
        // 3점에서 가운데(x=30)만 제거하면 양옆이 각각 1점 → 둘 다 버려져 빈 배열
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 60, y: 0)]
        let out = PathEraser.erase(pts, along: [CGPoint(x: 30, y: 0)], radius: 5)
        XCTAssertEqual(out.count, 0)
    }
}
