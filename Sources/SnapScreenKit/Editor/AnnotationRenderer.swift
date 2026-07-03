import AppKit
import CoreImage

public extension PaletteColor {
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .black: return .black
        case .white: return .white
        }
    }
}

/// 이미지 픽셀 좌표(원점 좌하단) CGContext에 주석을 그린다.
/// 캔버스 실시간 표시와 플래튼 내보내기가 공용으로 사용.
public enum AnnotationRenderer {
    public static func draw(_ annotations: [Annotation], in ctx: CGContext, baseImage: CGImage) {
        for annotation in annotations {
            draw(annotation, in: ctx, baseImage: baseImage)
        }
    }

    public static func draw(_ annotation: Annotation, in ctx: CGContext, baseImage: CGImage) {
        // Task 13에서 구현
    }
}
