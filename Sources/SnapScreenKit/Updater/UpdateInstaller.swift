import AppKit

/// 다운로드 → 압축 해제 → 검증 → 번들 교체 → 재실행.
/// 성공 시 NSApp.terminate로 돌아오지 않는다. 실패 시 에러 메시지를 반환한다.
@MainActor
public enum UpdateInstaller {
    /// 번들 교체는 성공했으나 자동 재실행 프로세스 기동에 실패한 경우 반환되는 메시지.
    /// (교체는 성공했으므로 "실패"가 아니라 안내로 표시해야 한다)
    public static let relaunchFailedMessage =
        L("The update is complete. If the app doesn't relaunch automatically, please launch it manually.")

    public static func install(version: String, downloadURL: URL) async -> String? {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("SnapScreenUpdate-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

            // 1. 다운로드
            let (downloaded, response) = try await URLSession.shared.download(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return L("Download failed (HTTP)")
            }
            let zip = workDir.appendingPathComponent("update.zip")
            try fm.moveItem(at: downloaded, to: zip)

            // 2. 압축 해제 (릴리스 zip을 만든 ditto와 동일 도구)
            let unzipDir = workDir.appendingPathComponent("unzipped")
            try runProcess("/usr/bin/ditto", ["-x", "-k", zip.path, unzipDir.path])

            // 3. 검증: 번들 존재 + 버전 일치
            let newApp = unzipDir.appendingPathComponent("SnapScreen.app")
            let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
            guard let plist = NSDictionary(contentsOf: plistURL),
                  plist["CFBundleShortVersionString"] as? String == version else {
                return L("Downloaded app failed validation")
            }

            // 4. 번들 교체 (실행 중 rename은 macOS에서 허용)
            let currentURL = Bundle.main.bundleURL
            let backupURL = workDir.appendingPathComponent("SnapScreen-old.app")
            do {
                try fm.moveItem(at: currentURL, to: backupURL)
            } catch {
                return L("Failed to replace app (check install folder permissions): \(error.localizedDescription)")
            }
            do {
                try fm.moveItem(at: newApp, to: currentURL)
            } catch {
                do {
                    try fm.moveItem(at: backupURL, to: currentURL) // 롤백
                    return L("Failed to replace app (check install folder permissions): \(error.localizedDescription)")
                } catch {
                    return L("An error occurred while replacing the app and recovery also failed. The previous version is at: \(backupURL.path)")
                }
            }

            // 5. 재실행: 분리 프로세스가 1초 후 새 번들을 열고, 현재 앱은 종료
            do {
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", currentURL.path]
                try relaunch.run()
            } catch {
                return relaunchFailedMessage
            }
            NSApp.terminate(nil)
            return nil // 도달하지 않음
        } catch {
            return L("Update failed: \(error.localizedDescription)")
        }
    }

    private static func runProcess(_ path: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""
            throw NSError(domain: "UpdateInstaller", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                                        L("\(path) exited with code \(Int(process.terminationStatus)): \(String(stderr.prefix(200)))")])
        }
    }
}
