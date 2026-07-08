import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class AnnotationStoreReplaceTests: XCTestCase {
    func testReplaceThenUndoRestoresPrevious() {
        let store = AnnotationStore()
        let a = Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10)))
        store.add(a)
        XCTAssertEqual(store.annotations.count, 1)

        let b = Annotation(kind: .ellipse(CGRect(x: 5, y: 5, width: 20, height: 20)))
        store.replace(with: [b])
        XCTAssertEqual(store.annotations.count, 1)
        XCTAssertEqual(store.annotations[0].id, b.id)

        store.undo()
        XCTAssertEqual(store.annotations.count, 1)
        XCTAssertEqual(store.annotations[0].id, a.id)

        store.redo()
        XCTAssertEqual(store.annotations[0].id, b.id)
    }

    func testReplaceWithEmptyClearsAndUndoRestores() {
        let store = AnnotationStore()
        store.add(Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 1, height: 1))))
        store.replace(with: [])
        XCTAssertTrue(store.annotations.isEmpty)
        store.undo()
        XCTAssertEqual(store.annotations.count, 1)
    }
}
