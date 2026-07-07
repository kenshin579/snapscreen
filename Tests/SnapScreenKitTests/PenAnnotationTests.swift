import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class PenAnnotationTests: XCTestCase {
    func testPathBoundsIsBoundingBox() {
        let kind = AnnotationKind.path([CGPoint(x: 10, y: 20), CGPoint(x: 40, y: 5),
                                        CGPoint(x: 25, y: 60)])
        let b = kind.bounds
        XCTAssertEqual(b.minX, 10, accuracy: 0.01)
        XCTAssertEqual(b.minY, 5, accuracy: 0.01)
        XCTAssertEqual(b.maxX, 40, accuracy: 0.01)
        XCTAssertEqual(b.maxY, 60, accuracy: 0.01)
    }

    func testEmptyPathBoundsIsZero() {
        XCTAssertEqual(AnnotationKind.path([]).bounds, .zero)
    }

    func testPathTranslatedMovesAllPoints() {
        let kind = AnnotationKind.path([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)])
        guard case .path(let pts) = kind.translated(by: CGVector(dx: 5, dy: -3)) else {
            return XCTFail("expected path")
        }
        XCTAssertEqual(pts[0], CGPoint(x: 5, y: -3))
        XCTAssertEqual(pts[1], CGPoint(x: 15, y: 7))
    }

    func testPathHitOnSegment() {
        let a = Annotation(kind: .path([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 3),
                                                    annotations: [a], tolerance: 8))
    }

    func testPathMissFarAway() {
        let a = Annotation(kind: .path([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]))
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 40),
                                                 annotations: [a], tolerance: 8))
    }
}
