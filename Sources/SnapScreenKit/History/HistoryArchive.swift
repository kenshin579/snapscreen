import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum HistoryError: Error { case encodeFailed }

/// 히스토리 파일 IO. 전부 동기·nonisolated라 임시 디렉터리로 단위 테스트 가능.
struct HistoryArchive: Sendable {
    let directory: URL

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    func pngURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }
    func thumbURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).thumb.png") }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 원본 PNG + 썸네일 저장. 성공 시 메타 반환.
    func write(image: CGImage, scale: CGFloat, id: UUID, date: Date) throws -> HistoryEntry {
        try ensureDirectory()
        guard let png = PNGEncoder.encode(image, scale: scale) else { throw HistoryError.encodeFailed }
        try png.write(to: pngURL(id))
        if let thumb = Self.thumbnailPNG(from: png, maxPixel: 320) {
            try? thumb.write(to: thumbURL(id)) // 썸네일 실패는 치명적 아님(원본으로 대체 가능)
        }
        return HistoryEntry(id: id, date: date, scale: scale)
    }

    func loadImage(id: UUID) -> CGImage? {
        guard let data = try? Data(contentsOf: pngURL(id)),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }

    /// index.json 로드 + 자가 치유(원본 파일 없는 항목 제거). 파싱 실패 시 빈 배열.
    func loadIndex() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
        return entries.filter { FileManager.default.fileExists(atPath: pngURL($0.id).path) }
    }

    func writeIndex(_ entries: [HistoryEntry]) {
        try? ensureDirectory()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: pngURL(id))
        try? FileManager.default.removeItem(at: thumbURL(id))
    }

    static func thumbnailPNG(from pngData: Data, maxPixel: CGFloat) -> Data? {
        guard let src = CGImageSourceCreateWithData(pngData as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
