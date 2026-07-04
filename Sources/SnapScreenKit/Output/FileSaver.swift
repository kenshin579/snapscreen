import CoreGraphics
import Foundation

public struct FileSaver {
    private let settings: SettingsStore
    private let resolver: SaveLocationResolver

    public init(settings: SettingsStore, resolver: SaveLocationResolver = SaveLocationResolver()) {
        self.settings = settings
        self.resolver = resolver
    }

    public enum Outcome {
        case saved(URL)
        case savedToFallback(URL)
        case failed(Error)
    }

    /// 사용자 설정 prefix에서 경로 구분자 등 위험 문자를 제거한다. 비면 기본값.
    static func sanitizedPrefix(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "snapscreen" : cleaned
    }

    /// 같은 이름이 이미 있으면 " (2)", " (3)"… 을 붙인다 (동일 초 연속 캡처 대응).
    static func uniqueURL(in directory: URL, filename: String,
                          fileManager: FileManager = .default) -> URL {
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var url = directory.appendingPathComponent(filename)
        var counter = 2
        while fileManager.fileExists(atPath: url.path) {
            url = directory.appendingPathComponent("\(base) (\(counter)).\(ext)")
            counter += 1
        }
        return url
    }

    public func save(_ image: CGImage, scale: CGFloat, date: Date = Date()) -> Outcome {
        guard let data = PNGEncoder.encode(image, scale: scale) else {
            return .failed(CocoaError(.fileWriteUnknown))
        }
        let prefix = Self.sanitizedPrefix(settings.filenamePrefix)
        let name = FilenameFormatter(prefix: prefix).filename(for: date)
        let dir = resolver.resolve(override: settings.saveFolderOverride)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = Self.uniqueURL(in: dir, filename: name)
            try data.write(to: url)
            return .saved(url)
        } catch {
            let desktop = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop")
            do {
                let fallback = Self.uniqueURL(in: desktop, filename: name)
                try data.write(to: fallback)
                return .savedToFallback(fallback)
            } catch {
                return .failed(error)
            }
        }
    }
}
