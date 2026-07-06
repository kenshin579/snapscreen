import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class PathSmootherTests: XCTestCase {
    func testEmptyPointsGivesEmptyPath() {
        XCTAssertTrue(PathSmoother.smoothedPath([]).isEmpty)
    }

    func testSinglePointNotEmpty() {
        let path = PathSmoother.smoothedPath([CGPoint(x: 10, y: 10)])
        XCTAssertFalse(path.isEmpty)
    }

    func testTwoPointsIsStraightLine() {
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 100, y: 40)
        let path = PathSmoother.smoothedPath([a, b])
        XCTAssertEqual(path.currentPoint.x, 100, accuracy: 0.01)
        XCTAssertEqual(path.currentPoint.y, 40, accuracy: 0.01)
        let box = path.boundingBoxOfPath
        XCTAssertEqual(box.minX, 0, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 100, accuracy: 0.01)
    }

    func testMultiPointEndsAtLastPoint() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 80),
                   CGPoint(x: 100, y: 0), CGPoint(x: 150, y: 80)]
        let path = PathSmoother.smoothedPath(pts)
        XCTAssertEqual(path.currentPoint.x, 150, accuracy: 0.01)
        XCTAssertEqual(path.currentPoint.y, 80, accuracy: 0.01)
        XCTAssertFalse(path.isEmpty)
    }
}
