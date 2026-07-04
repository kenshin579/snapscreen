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
@MainActor
public enum AnnotationRenderer {
    public static func draw(_ annotations: [Annotation], in ctx: CGContext,
                            baseImage: CGImage, scale: CGFloat) {
        for annotation in annotations {
            draw(annotation, in: ctx, baseImage: baseImage, scale: scale)
        }
    }

    public static func draw(_ annotation: Annotation, in ctx: CGContext,
                            baseImage: CGImage, scale: CGFloat) {
        let color = annotation.color.nsColor.cgColor
        switch annotation.kind {
        case .arrow(let start, let end):
            drawArrow(from: start, to: end, color: color,
                      lineWidth: annotation.lineWidth, in: ctx)
        case .rectangle(let rect):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.stroke(rect)
        case .ellipse(let rect):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.strokeEllipse(in: rect)
        case .text(let origin, let string, let fontSize):
            drawText(string, at: origin, fontSize: fontSize,
                     color: annotation.color.nsColor, in: ctx)
        case .pixelate(let rect):
            if let cached = pixelateCache[annotation.id], cached.rect == rect {
                ctx.draw(cached.image, in: cached.clamped)
            } else if let result = pixelatedImage(from: baseImage, rect: rect, scale: scale) {
                if pixelateCache.count >= 64 { pixelateCache.removeAll() } // 무한 성장 방지
                pixelateCache[annotation.id] = (rect, result.image, result.rect)
                ctx.draw(result.image, in: result.rect)
            }
        case .stepBadge(let center, let number, let radius):
            drawBadge(number: number, center: center, radius: radius,
                      color: annotation.color.nsColor, in: ctx)
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint,
                                  color: CGColor, lineWidth: CGFloat, in ctx: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(lineWidth * 4, 16)
        // 몸통은 화살촉 밑까지만
        let bodyEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.8,
                              y: end.y - sin(angle) * headLength * 0.8)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addLine(to: bodyEnd)
        ctx.strokePath()

        let headAngle: CGFloat = .pi / 7
        let left = CGPoint(x: end.x - cos(angle - headAngle) * headLength,
                           y: end.y - sin(angle - headAngle) * headLength)
        let right = CGPoint(x: end.x - cos(angle + headAngle) * headLength,
                            y: end.y - sin(angle + headAngle) * headLength)
        ctx.setFillColor(color)
        ctx.move(to: end)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat,
                                 color: NSColor, in ctx: CGContext) {
        // 현재 NSGraphicsContext가 이 ctx를 감싸도록 보장 (CanvasView.draw 안에서는 이미 그렇고,
        // FlattenRenderer도 설정해 준다)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: color
        ]
        NSAttributedString(string: string, attributes: attrs).draw(at: origin)
    }

    private static let ciContext = CIContext()

    /// 픽셀레이트 결과 캐시 — 매 draw마다 CIFilter 재실행을 피한다 (드래그 리렌더 잔크 방지).
    /// baseImage는 편집기 세션 동안 불변이므로 rect 비교만으로 무효화 가능.
    private static var pixelateCache: [UUID: (rect: CGRect, image: CGImage, clamped: CGRect)] = [:]

    static func pixelatedImage(from base: CGImage, rect: CGRect,
                               scale: CGFloat) -> (image: CGImage, rect: CGRect)? {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !clamped.isEmpty else { return nil }
        let input = CIImage(cgImage: base).cropped(to: clamped)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        // 복원 공격 방지: 영역이 커도 블록이 충분히 크도록. Retina(2x)에서는 바닥값도 2배.
        let blockSize = max(12 * scale, clamped.width / 24, clamped.height / 24)
        filter.setValue(blockSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: clamped.midX, y: clamped.midY), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: clamped) else { return nil }
        guard let image = ciContext.createCGImage(output, from: clamped) else { return nil }
        return (image, clamped)
    }

    private static func drawBadge(number: Int, center: CGPoint, radius: CGFloat,
                                  color: NSColor, in ctx: CGContext) {
        let circle = CGRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: circle)

        let label = "\(number)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: radius * 1.1),
            .foregroundColor: color == .white ? NSColor.black : NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: center.x - size.width / 2,
                               y: center.y - size.height / 2),
                   withAttributes: attrs)
    }
}
