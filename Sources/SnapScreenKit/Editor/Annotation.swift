import Foundation
import CoreGraphics

public enum PaletteColor: String, CaseIterable, Equatable, Codable {
    case red, orange, green, blue, black, white
}

public enum AnnotationKind: Equatable {
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case text(origin: CGPoint, string: String, fontSize: CGFloat)
    case pixelate(CGRect)
    case blur(CGRect)
    case stepBadge(center: CGPoint, number: Int, radius: CGFloat)
    case path([CGPoint])

    public func translated(by d: CGVector) -> AnnotationKind {
        switch self {
        case .arrow(let s, let e):
            return .arrow(start: CGPoint(x: s.x + d.dx, y: s.y + d.dy),
                          end: CGPoint(x: e.x + d.dx, y: e.y + d.dy))
        case .rectangle(let r): return .rectangle(r.offsetBy(dx: d.dx, dy: d.dy))
        case .ellipse(let r): return .ellipse(r.offsetBy(dx: d.dx, dy: d.dy))
        case .text(let o, let s, let f):
            return .text(origin: CGPoint(x: o.x + d.dx, y: o.y + d.dy), string: s, fontSize: f)
        case .pixelate(let r): return .pixelate(r.offsetBy(dx: d.dx, dy: d.dy))
        case .blur(let r): return .blur(r.offsetBy(dx: d.dx, dy: d.dy))
        case .stepBadge(let c, let n, let r):
            return .stepBadge(center: CGPoint(x: c.x + d.dx, y: c.y + d.dy), number: n, radius: r)
        case .path(let pts):
            return .path(pts.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) })
        }
    }

    /// 히트 테스트/다시그리기용 대략적 경계 (이미지 픽셀 좌표)
    public var bounds: CGRect {
        switch self {
        case .arrow(let s, let e):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(s.x - e.x), height: abs(s.y - e.y))
        case .rectangle(let r), .ellipse(let r), .pixelate(let r), .blur(let r):
            return r
        case .text(let o, let s, let f):
            // AppKit 없이 근사: 라틴 0.6em, CJK 1.0em. 높이 1.3em
            let width = s.reduce(CGFloat(0)) { acc, ch in
                acc + (ch.isASCII ? f * 0.6 : f * 1.0)
            }
            return CGRect(x: o.x, y: o.y, width: width, height: f * 1.3)
        case .stepBadge(let c, _, let r):
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        case .path(let pts):
            guard let first = pts.first else { return .zero }
            var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
            for p in pts.dropFirst() {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
}

public struct Annotation: Equatable, Identifiable {
    public let id: UUID
    public var kind: AnnotationKind
    public var color: PaletteColor
    public var lineWidth: CGFloat

    public init(id: UUID = UUID(), kind: AnnotationKind,
                color: PaletteColor = .red, lineWidth: CGFloat = 4) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }
}
