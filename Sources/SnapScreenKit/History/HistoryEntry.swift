import Foundation
import CoreGraphics

/// 히스토리 항목 메타데이터. 실제 이미지는 <id>.png / <id>.thumb.png로 저장된다.
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let scale: CGFloat   // 재편집 시 Retina 배율 복원에 필수

    public init(id: UUID, date: Date, scale: CGFloat) {
        self.id = id
        self.date = date
        self.scale = scale
    }
}
