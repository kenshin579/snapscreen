import CoreGraphics

/// 자유곡선 점열을 부드러운 CGPath로 변환하는 순수 함수 (이차 베지어 중점 스무딩).
/// 저장 모델은 raw 점열이고, 이 변환은 렌더 시에만 쓰인다. AppKit 비의존 → 단위 테스트 가능.
public enum PathSmoother {
    public static func smoothedPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        if points.count == 1 {
            path.addLine(to: first) // round cap이면 점 하나가 원형 점으로 찍힘
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 1..<(points.count - 1) {
            let control = points[i]
            let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2,
                              y: (points[i].y + points[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: control)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }
}
