import XCTest
@testable import SnapScreenKit

final class ScreenGeometryTests: XCTestCase {
    func testCGRectConversionPrimaryScreen() {
        // 1920x1080 화면(원점 0,0)에서 좌상단 근처 100pt 정사각형
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 10, y: 970, width: 100, height: 100) // Cocoa: 좌하단 원점
        let cg = ScreenGeometry.cgRect(fromScreenRect: selection, screenFrame: screen)
        XCTAssertEqual(cg, CGRect(x: 10, y: 10, width: 100, height: 100)) // CG: 좌상단 원점
    }

    func testCGRectConversionSecondaryScreen() {
        // 주 화면 오른쪽에 붙은 보조 화면 (Cocoa 전역 좌표에서 x=1920 시작)
        let screen = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 1920 + 50, y: 0, width: 200, height: 100) // 화면 좌하단
        let cg = ScreenGeometry.cgRect(fromScreenRect: selection, screenFrame: screen)
        XCTAssertEqual(cg, CGRect(x: 50, y: 800, width: 200, height: 100))
    }

    func testPixelSize() {
        let px = ScreenGeometry.pixelSize(pointSize: CGSize(width: 100, height: 50), scale: 2)
        XCTAssertEqual(px, CGSize(width: 200, height: 100))
    }
}
