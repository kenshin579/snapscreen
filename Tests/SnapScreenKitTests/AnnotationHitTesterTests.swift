import XCTest
@testable import SnapScreenKit

final class AnnotationHitTesterTests: XCTestCase {
    func testArrowHit() {
        let a = Annotation(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 5), annotations: [a]))
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 30), annotations: [a]))
    }

    func testRectangleHitsBorderNotInside() {
        let a = Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 0, y: 50), annotations: [a]))   // 테두리
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 50), annotations: [a]))     // 내부
    }

    func testPixelateHitsInside() {
        let a = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 50), annotations: [a]))
    }

    func testBadgeHit() {
        let a = Annotation(kind: .stepBadge(center: CGPoint(x: 50, y: 50), number: 1, radius: 14))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 55, y: 55), annotations: [a]))
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 90, y: 90), annotations: [a]))
    }

    func testBlurHitsInside() {
        let a = Annotation(kind: .blur(CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 50), annotations: [a]))
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 200, y: 200), annotations: [a]))
    }

    func testTopmostWins() {
        let bottom = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let top = Annotation(kind: .pixelate(CGRect(x: 40, y: 40, width: 100, height: 100)))
        let hit = AnnotationHitTester.hitTest(CGPoint(x: 50, y: 50), annotations: [bottom, top])
        XCTAssertEqual(hit?.id, top.id)
    }
}
