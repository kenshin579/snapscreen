import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class HistoryArchiveTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-test-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func solidImage(_ w: Int = 40, _ h: Int = 30) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    func testWriteCreatesFilesAndEntry() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        let entry = try archive.write(image: solidImage(), scale: 2, id: id, date: Date())
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.scale, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.pngURL(id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.thumbURL(id).path))
    }

    func testSweepOrphansRemovesUnindexedFiles() throws {
        let archive = HistoryArchive(directory: dir)
        let keep = UUID(), orphan = UUID()
        _ = try archive.write(image: solidImage(), scale: 1, id: keep, date: Date())
        _ = try archive.write(image: solidImage(), scale: 1, id: orphan, date: Date())
        archive.sweepOrphans(keeping: [keep])
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.pngURL(keep).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.pngURL(orphan).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.thumbURL(orphan).path))
    }

    func testLoadImageRoundTrips() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        _ = try archive.write(image: solidImage(40, 30), scale: 1, id: id, date: Date())
        let loaded = archive.loadImage(id: id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.width, 40)
        XCTAssertEqual(loaded?.height, 30)
    }

    func testIndexRoundTripsAndSelfHeals() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        _ = try archive.write(image: solidImage(), scale: 1, id: id, date: Date())
        let phantom = HistoryEntry(id: UUID(), date: Date(), scale: 1) // 파일 없는 항목
        let real = HistoryEntry(id: id, date: Date(), scale: 1)
        archive.writeIndex([phantom, real])
        let loaded = archive.loadIndex()
        // 파일 있는 항목만 남는다(자가 치유)
        XCTAssertEqual(loaded.map(\.id), [id])
    }

    func testCorruptIndexReturnsEmpty() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("index.json"))
        let archive = HistoryArchive(directory: dir)
        XCTAssertEqual(archive.loadIndex(), [])
    }

    func testDeleteRemovesFiles() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        _ = try archive.write(image: solidImage(), scale: 1, id: id, date: Date())
        archive.delete(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.pngURL(id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.thumbURL(id).path))
    }
}
