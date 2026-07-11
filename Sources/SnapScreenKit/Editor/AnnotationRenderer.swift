import AppKit
import CoreImage

public extension PaletteColor {
    var nsColor: NSColor {
        func dyn(_ light: UInt32, _ dark: UInt32) -> NSColor {
            NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    ? NSColor(hex: dark) : NSColor(hex: light)
            }
        }
        switch self {
        case .red:    return dyn(0xFF3B30, 0xFF453A)
        case .orange: return dyn(0xFF9500, 0xFF9F0A)
        case .yellow: return dyn(0xFFCC00, 0xFFD60A)
        case .green:  return dyn(0x34C759, 0x30D158)
        case .blue:   return dyn(0x007AFF, 0x0A84FF)
        case .label:  return dyn(0x1D1D1F, 0xF5F5F7)
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
        // pixelate/blur는 이미지 영역이라 그림자 제외(보안 목적·시각 훼손 방지)
        let castsShadow: Bool = {
            guard annotation.shadowEnabled else { return false }
            switch annotation.kind {
            case .pixelate, .blur: return false
            default: return true
            }
        }()
        if castsShadow {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -2 * scale),
                          blur: 4 * scale,
                          color: NSColor(white: 0, alpha: 0.35).cgColor)
        }
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
        case .blur(let rect):
            if let cached = pixelateCache[annotation.id], cached.rect == rect {
                ctx.draw(cached.image, in: cached.clamped)
            } else if let result = blurredImage(from: baseImage, rect: rect, scale: scale) {
                if pixelateCache.count >= 64 { pixelateCache.removeAll() } // 무한 성장 방지
                pixelateCache[annotation.id] = (rect, result.image, result.rect)
                ctx.draw(result.image, in: result.rect)
            }
        case .stepBadge(let center, let number, let radius):
            drawBadge(number: number, center: center, radius: radius,
                      color: annotation.color.nsColor, in: ctx)
        case .path(let points):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(PathSmoother.smoothedPath(points))
            ctx.strokePath()
        }
        if castsShadow { ctx.restoreGState() }
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

    /// 픽셀레이트/블러 결과 캐시 — 매 draw마다 CIFilter 재실행을 피한다 (드래그 리렌더 잔크 방지).
    /// baseImage는 편집기 세션 동안 불변이므로 rect 비교만으로 무효화 가능. 키는 annotation UUID라
    /// 두 도구가 공유해도 충돌 없음.
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

    /// 가우시안 블러 — 시각적 완화용. 민감정보 가리기에는 모자이크(pixelate)를 권장
    /// (약한 가우시안 블러는 복원 공격 가능).
    static func blurredImage(from base: CGImage, rect: CGRect,
                             scale: CGFloat) -> (image: CGImage, rect: CGRect)? {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !clamped.isEmpty else { return nil }
        // crop 후 clampedToExtent: 영역 가장자리 픽셀을 복제해 블러가 경계 밖 투명 픽셀로
        // 어두워지는 것을 방지한다. 의도적으로 영역 밖 실제 픽셀은 섞지 않는다(자기 완결 블러) —
        // 인접 콘텐츠가 블러 영역으로 새지 않고, 이미지 경계에서도 동일하게 동작한다.
        let input = CIImage(cgImage: base).cropped(to: clamped).clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        let radius = max(8 * scale, min(clamped.width, clamped.height) / 24)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
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
            .foregroundColor: color.ks_isLight ? NSColor.black : NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: center.x - size.width / 2,
                               y: center.y - size.height / 2),
                   withAttributes: attrs)
    }
}

private extension NSColor {
    /// 배지 글자색 대비용 상대 명도 판정. 동적 색은 현재 NSAppearance 기준으로 해석된다.
    var ks_isLight: Bool {
        guard let c = usingColorSpace(.sRGB) else { return false }
        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
        return lum > 0.6
    }
}
