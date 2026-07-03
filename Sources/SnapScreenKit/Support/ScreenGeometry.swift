import CoreGraphics
import Foundation

public enum ScreenGeometry {
    /// Cocoa 전역 좌표(원점 좌하단) rect → 해당 디스플레이 로컬 CG 좌표(원점 좌상단)
    /// SCStreamConfiguration.sourceRect가 요구하는 좌표계.
    public static func cgRect(fromScreenRect rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX,
               y: screenFrame.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    public static func pixelSize(pointSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
    }
}
