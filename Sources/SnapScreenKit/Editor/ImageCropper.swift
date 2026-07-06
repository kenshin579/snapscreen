import CoreGraphics

/// 이미지 자르기. rect는 이미지 픽셀 좌표(원점 좌하단, 코드베이스 규약).
/// CGImage.cropping(to:)은 데이터가 좌상단 원점이라 y를 뒤집는다.
public enum ImageCropper {
    public static func crop(_ image: CGImage, toBottomLeftRect rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let clamped = rect.integral.intersection(bounds)
        guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
        // 좌하단 → 좌상단 y 뒤집기
        let topLeft = CGRect(x: clamped.minX,
                             y: CGFloat(image.height) - clamped.maxY,
                             width: clamped.width,
                             height: clamped.height)
        return image.cropping(to: topLeft)
    }
}
