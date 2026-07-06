import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class ImageCropperTests: XCTestCase {
    /// 좌하단 절반은 빨강, 상단 절반은 파랑인 이미지 (좌하단 원점 검증용)
    private func makeHalfImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGContext는 좌하단 원점: y=0..height/2 가 하단
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))            // 하단 빨강
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))   // 상단 파랑
        return ctx.makeImage()!
    }

    /// 이미지의 (x,y) 픽셀 색을 [R,G,B,A]로 (좌하단 원점 — CGContext에 그려서 샘플)
    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(y),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        return data
    }

    func testCropSize() {
        let base = makeHalfImage(width: 200, height: 100)
        let out = ImageCropper.crop(base, toBottomLeftRect: CGRect(x: 10, y: 20, width: 50, height: 30))
        XCTAssertEqual(out?.width, 50)
        XCTAssertEqual(out?.height, 30)
    }

    func testCropBottomHalfIsRed() {
        // 좌하단 원점 rect가 하단(빨강) 영역을 정확히 집어내는지 — y 뒤집기 검증
        let base = makeHalfImage(width: 200, height: 100)
        let out = ImageCropper.crop(base, toBottomLeftRect: CGRect(x: 0, y: 0, width: 200, height: 40))!
        let p = pixel(out, x: 100, y: 20)   // crop 결과의 중앙
        XCTAssertGreaterThan(p[0], 200)     // 빨강
        XCTAssertLessThan(p[2], 50)         // 파랑 아님
    }

    func testCropTopHalfIsBlue() {
        let base = makeHalfImage(width: 200, height: 100)
        let out = ImageCropper.crop(base, toBottomLeftRect: CGRect(x: 0, y: 60, width: 200, height: 40))!
        let p = pixel(out, x: 100, y: 20)
        XCTAssertGreaterThan(p[2], 200)     // 파랑
        XCTAssertLessThan(p[0], 50)         // 빨강 아님
    }

    func testClampsToBounds() {
        // 이미지 밖으로 나간 rect는 경계로 클램프
        let base = makeHalfImage(width: 200, height: 100)
        let out = ImageCropper.crop(base, toBottomLeftRect: CGRect(x: 180, y: 90, width: 100, height: 100))
        XCTAssertEqual(out?.width, 20)   // 200-180
        XCTAssertEqual(out?.height, 10)  // 100-90
    }

    func testEmptyRectReturnsNil() {
        let base = makeHalfImage(width: 200, height: 100)
        XCTAssertNil(ImageCropper.crop(base, toBottomLeftRect: CGRect(x: 300, y: 300, width: 10, height: 10)))
        XCTAssertNil(ImageCropper.crop(base, toBottomLeftRect: .zero))
    }
}
