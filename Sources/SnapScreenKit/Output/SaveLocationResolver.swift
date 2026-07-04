import Foundation

public protocol SystemLocationReading {
    func screencaptureLocation() -> String?
}

/// macOS 스크린샷 앱(cmd+shift+5)에서 설정한 저장 위치를 읽는다.
public struct SystemLocationReader: SystemLocationReading {
    public init() {}
    public func screencaptureLocation() -> String? {
        CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
    }
}

public struct SaveLocationResolver {
    private let system: SystemLocationReading
    private let fileManager: FileManager

    public init(system: SystemLocationReading = SystemLocationReader(),
                fileManager: FileManager = .default) {
        self.system = system
        self.fileManager = fileManager
    }

    /// 우선순위: 설정 오버라이드 > 시스템 스크린샷 위치 > ~/Desktop
    public func resolve(override: String?) -> URL {
        for candidate in [override, system.screencaptureLocation()] {
            guard let candidate, !candidate.isEmpty else { continue }
            let path = (candidate as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
    }
}
