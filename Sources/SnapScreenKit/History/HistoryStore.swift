import Foundation
import CoreGraphics

/// 히스토리 상태 래퍼. entries(최신순)를 노출하고 50개 상한 롤링을 관리한다.
/// 인코딩/디스크 쓰기는 백그라운드에서 수행하고 결과만 메인에서 반영(캡처 흐름 비차단).
@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var entries: [HistoryEntry] = []
    private let archive: HistoryArchive
    private var limit: Int

    public init(directory: URL, limit: Int = 50) {
        self.archive = HistoryArchive(directory: directory)
        self.limit = limit
        let loaded = archive.loadIndex().sorted { $0.date > $1.date }
        entries = loaded
        archive.sweepOrphans(keeping: Set(loaded.map(\.id)))
    }

    public func add(image: CGImage, scale: CGFloat, id: UUID = UUID(), date: Date = Date()) {
        let archive = self.archive
        DispatchQueue.global(qos: .utility).async {
            guard let entry = try? archive.write(image: image, scale: scale, id: id, date: date) else { return }
            Task { @MainActor in self.insert(entry) }
        }
    }

    private func insert(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }        // 동일 id 재추가 방지
        entries.append(entry)
        entries.sort { $0.date > $1.date }             // 최신순
        while entries.count > limit {
            let removed = entries.removeLast()
            archive.delete(id: removed.id)
        }
        archive.writeIndex(entries)
    }

    public func loadImage(id: UUID) -> CGImage? { archive.loadImage(id: id) }
    public func thumbnailURL(id: UUID) -> URL { archive.thumbURL(id) }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        archive.delete(id: id)
        archive.writeIndex(entries)
    }

    /// 히스토리 전체 삭제 (파일 + 메타)
    public func clear() {
        for entry in entries { archive.delete(id: entry.id) }
        entries = []
        archive.writeIndex(entries)
    }

    /// 보관 개수 변경. 줄이면 초과분(오래된 것부터)을 즉시 삭제한다.
    public func updateLimit(_ newLimit: Int) {
        limit = newLimit
        while entries.count > limit {
            let removed = entries.removeLast()
            archive.delete(id: removed.id)
        }
        archive.writeIndex(entries)
    }
}
