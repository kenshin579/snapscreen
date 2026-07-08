import CoreGraphics

/// 자유곡선 점열에서 지우개 경로(centers) 반경 안의 점을 제거하고,
/// 남은 인덱스-연속 구간을 조각으로 분리하는 순수 함수. AppKit 비의존.
public enum PathEraser {
    public static func erase(_ points: [CGPoint],
                             along centers: [CGPoint],
                             radius: CGFloat) -> [[CGPoint]] {
        guard !points.isEmpty else { return [] }
        func isErased(_ p: CGPoint) -> Bool {
            centers.contains { hypot(p.x - $0.x, p.y - $0.y) <= radius }
        }
        var segments: [[CGPoint]] = []
        var current: [CGPoint] = []
        var erasedAny = false
        for p in points {
            if isErased(p) {
                erasedAny = true
                if current.count >= 2 { segments.append(current) }
                current = []
            } else {
                current.append(p)
            }
        }
        if current.count >= 2 { segments.append(current) }
        if !erasedAny { return [points] }
        return segments
    }
}
