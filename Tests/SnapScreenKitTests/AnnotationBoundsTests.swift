import XCTest
@testable import SnapScreenKit

final class AnnotationBoundsTests: XCTestCase {
    func testTextBoundsMixedCJK() {
        let kind = AnnotationKind.text(origin: .zero, string: "ab한", fontSize: 16)
        XCTAssertEqual(kind.bounds.width, 16 * 0.6 * 2 + 16 * 1.0, accuracy: 0.001)
        XCTAssertEqual(kind.bounds.height, 16 * 1.3, accuracy: 0.001)
    }
}
