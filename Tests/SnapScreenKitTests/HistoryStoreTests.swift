import XCTest
import CoreGraphics
@testable import SnapScreenKit

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-store-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func solidImage() -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        return ctx.makeImage()!
    }

    func testAddInsertsNewestFirst() async throws {
        let store = HistoryStore(directory: dir, limit: 50)
        store.add(image: solidImage(), scale: 1, id: UUID(), date: Date(timeIntervalSince1970: 100))
        store.add(image: solidImage(), scale: 1, id: UUID(), date: Date(timeIntervalSince1970: 200))
        try await waitUntil { store.entries.count == 2 }
        XCTAssertEqual(store.entries.first?.date, Date(timeIntervalSince1970: 200)) // 최신 먼저
    }

    func testRollingDropsOldest() async throws {
        let store = HistoryStore(directory: dir, limit: 3)
        var ids: [UUID] = []
        for i in 0..<4 {
            let id = UUID(); ids.append(id)
            store.add(image: solidImage(), scale: 1, id: id, date: Date(timeIntervalSince1970: Double(i)))
        }
        try await waitUntil { store.entries.count == 3 }
        XCTAssertFalse(store.entries.contains { $0.id == ids[0] }) // 가장 오래된 것 제거
    }

    func testRemoveDeletesEntryAndReloadsEmpty() async throws {
        let store = HistoryStore(directory: dir, limit: 50)
        let id = UUID()
        store.add(image: solidImage(), scale: 3, id: id, date: Date())
        try await waitUntil { store.entries.count == 1 }
        XCTAssertEqual(store.entries.first?.scale, 3) // scale 왕복

        store.remove(id: id)
        XCTAssertTrue(store.entries.isEmpty)
        // 새 store로 재로드해도 비어 있음(index/파일 삭제 확인)
        let reloaded = HistoryStore(directory: dir, limit: 50)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    /// 조건이 참이 될 때까지 최대 2초 폴링(add가 비동기 인코딩이라)
    private func waitUntil(_ cond: @escaping () -> Bool) async throws {
        for _ in 0..<200 {
            if cond() { return }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        XCTFail("조건 미충족(timeout)")
    }
}
