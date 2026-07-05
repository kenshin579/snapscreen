import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class BlurRenderTests: XCTestCase {
    /// 수평 그라데이션 이미지 (블러 효과 검증용)
    private func makeGradient(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for x in 0..<width {
            let v = CGFloat(x) / CGFloat(width)
            ctx.setFillColor(CGColor(red: v, green: 1 - v, blue: 0.5, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: height))
        }
        return ctx.makeImage()!
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &data, width: 1, height: 1,
                            bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -CGFloat(x), y: -CGFloat(y),
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        return data
    }

    @MainActor
    func testBlurredImageActuallyBlurs() {
        let base = makeGradient(width: 96, height: 96)
        let rect = CGRect(x: 8, y: 8, width: 80, height: 80)
        guard let result = AnnotationRenderer.blurredImage(from: base, rect: rect, scale: 2) else {
            return XCTFail("blurredImage returned nil")
        }
        XCTAssertEqual(result.rect, rect)
        // 그라데이션 좌단이 이웃 픽셀과 섞여 원본과 달라져야 한다
        let originalLeft = pixel(base, x: 10, y: 48)
        let blurredLeft = pixel(result.image, x: 2, y: 40) // result 이미지는 clamped 기준 로컬 좌표
        XCTAssertNotEqual(originalLeft, blurredLeft, "블러 결과가 원본과 동일 — 블러가 적용되지 않음")
    }

    @MainActor
    func testBlurredImageCornersNotDarkened() {
        // 단색 이미지를 블러하면 모서리도 같은 색이어야 한다 (clampedToExtent 회귀 가드)
        let ctx = CGContext(data: nil, width: 64, height: 64,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let base = ctx.makeImage()!

        guard let result = AnnotationRenderer.blurredImage(
            from: base, rect: CGRect(x: 0, y: 0, width: 64, height: 64), scale: 1) else {
            return XCTFail("blurredImage returned nil")
        }
        let corner = pixel(result.image, x: 1, y: 1)
        XCTAssertGreaterThan(corner[0], 240, "모서리가 어두워짐 — clampedToExtent 회귀")
        XCTAssertGreaterThan(corner[3], 240, "모서리 알파 소실")
    }
}
