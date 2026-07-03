import AppKit

@MainActor
public enum FlattenRenderer {
    public static func flatten(image: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // 텍스트 렌더링(NSAttributedString.draw)이 현재 NSGraphicsContext를 요구한다
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        AnnotationRenderer.draw(annotations, in: ctx, baseImage: image)
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }
}
