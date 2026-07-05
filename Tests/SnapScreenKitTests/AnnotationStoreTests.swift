import XCTest
@testable import SnapScreenKit

final class AnnotationStoreTests: XCTestCase {
    private func rect(_ x: CGFloat = 0, _ y: CGFloat = 0) -> Annotation {
        Annotation(kind: .rectangle(CGRect(x: x, y: y, width: 100, height: 50)))
    }

    func testAddAndUndoRedo() {
        let store = AnnotationStore()
        XCTAssertFalse(store.canUndo)

        let a = rect()
        store.add(a)
        XCTAssertEqual(store.annotations, [a])
        XCTAssertTrue(store.canUndo)

        store.undo()
        XCTAssertEqual(store.annotations, [])
        XCTAssertTrue(store.canRedo)

        store.redo()
        XCTAssertEqual(store.annotations, [a])
    }

    func testNewActionClearsRedoStack() {
        let store = AnnotationStore()
        store.add(rect())
        store.undo()
        store.add(rect(10, 10))
        XCTAssertFalse(store.canRedo)
    }

    func testRemove() {
        let store = AnnotationStore()
        let a = rect()
        store.add(a)
        store.remove(id: a.id)
        XCTAssertEqual(store.annotations, [])
        store.undo()
        XCTAssertEqual(store.annotations, [a])
    }

    func testTranslate() {
        let store = AnnotationStore()
        let a = Annotation(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10)))
        store.add(a)
        store.translate(id: a.id, by: CGVector(dx: 5, dy: -3))
        guard case .arrow(let s, let e) = store.annotations[0].kind else {
            return XCTFail("kind changed")
        }
        XCTAssertEqual(s, CGPoint(x: 5, y: -3))
        XCTAssertEqual(e, CGPoint(x: 15, y: 7))
    }

    func testNextStepNumber() {
        let store = AnnotationStore()
        XCTAssertEqual(store.nextStepNumber, 1)
        store.add(Annotation(kind: .stepBadge(center: .zero, number: 1, radius: 14)))
        store.add(Annotation(kind: .stepBadge(center: .zero, number: 2, radius: 14)))
        XCTAssertEqual(store.nextStepNumber, 3)
        // 2번 배지를 지워도 최대값 기준으로 증가한다
        store.remove(id: store.annotations[0].id)
        XCTAssertEqual(store.nextStepNumber, 3)
    }

    func testTranslateBlur() {
        let store = AnnotationStore()
        let a = Annotation(kind: .blur(CGRect(x: 10, y: 20, width: 100, height: 50)))
        store.add(a)
        store.translate(id: a.id, by: CGVector(dx: 5, dy: -5))
        guard case .blur(let r) = store.annotations[0].kind else {
            return XCTFail("kind changed")
        }
        XCTAssertEqual(r, CGRect(x: 15, y: 15, width: 100, height: 50))
    }
}
