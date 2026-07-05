import Foundation
import CoreGraphics

public enum AnnotationHitTester {
    /// 위(나중에 그린 것)부터 검사. point는 이미지 픽셀 좌표.
    public static func hitTest(_ point: CGPoint, annotations: [Annotation],
                               tolerance: CGFloat = 8) -> Annotation? {
        annotations.reversed().first { hits(point, $0, tolerance) }
    }

    private static func hits(_ p: CGPoint, _ a: Annotation, _ tol: CGFloat) -> Bool {
        switch a.kind {
        case .arrow(let s, let e):
            return distanceToSegment(p, s, e) <= tol
        case .rectangle(let r), .ellipse(let r):
            // 테두리 스트로크만 잡는다 (내부는 통과 — 아래 주석 선택 가능하게)
            let outer = r.insetBy(dx: -tol, dy: -tol)
            let inner = r.insetBy(dx: tol, dy: tol)
            let insideInner = inner.width > 0 && inner.height > 0 && inner.contains(p)
            return outer.contains(p) && !insideInner
        case .text, .pixelate, .blur:
            return a.kind.bounds.insetBy(dx: -tol, dy: -tol).contains(p)
        case .stepBadge(let c, _, let r):
            return hypot(p.x - c.x, p.y - c.y) <= r + tol
        }
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / lengthSquared))
        let proj = CGPoint(x: a.x + t * ab.dx, y: a.y + t * ab.dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
