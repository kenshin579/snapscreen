import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class FlattenRendererTests: XCTestCase {
    private func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    @MainActor
    func testFlattenPreservesDimensions() {
        let base = makeImage(width: 200, height: 100)
        let out = FlattenRenderer.flatten(image: base, annotations: [], scale: 1)
        XCTAssertEqual(out?.width, 200)
        XCTAssertEqual(out?.height, 100)
    }

    @MainActor
    func testFlattenWithAnnotationPreservesDimensions() {
        let base = makeImage(width: 200, height: 100)
        let a = Annotation(kind: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 30)))
        let out = FlattenRenderer.flatten(image: base, annotations: [a], scale: 2)
        XCTAssertEqual(out?.width, 200)
        XCTAssertEqual(out?.height, 100)
    }

    @MainActor
    func testFlattenWithBlurPreservesDimensions() {
        let base = makeImage(width: 200, height: 100)
        let a = Annotation(kind: .blur(CGRect(x: 10, y: 10, width: 80, height: 40)))
        let out = FlattenRenderer.flatten(image: base, annotations: [a], scale: 2)
        XCTAssertEqual(out?.width, 200)
        XCTAssertEqual(out?.height, 100)
    }
}
