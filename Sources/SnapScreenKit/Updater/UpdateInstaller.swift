import AppKit

/// 다운로드 → 압축 해제 → 검증 → 번들 교체 → 재실행.
/// 성공 시 NSApp.terminate로 돌아오지 않는다. 실패 시 에러 메시지를 반환한다.
@MainActor
public enum UpdateInstaller {
    public static func install(version: String, downloadURL: URL) async -> String? {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("SnapScreenUpdate-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

            // 1. 다운로드
            let (downloaded, response) = try await URLSession.shared.download(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "다운로드 실패 (HTTP)"
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
                return "다운로드한 앱 검증에 실패했습니다"
            }

            // 4. 번들 교체 (실행 중 rename은 macOS에서 허용)
            let currentURL = Bundle.main.bundleURL
            let backupURL = workDir.appendingPathComponent("SnapScreen-old.app")
            do {
                try fm.moveItem(at: currentURL, to: backupURL)
            } catch {
                return "앱 교체에 실패했습니다 (설치 폴더 권한 확인): \(error.localizedDescription)"
            }
            do {
                try fm.moveItem(at: newApp, to: currentURL)
            } catch {
                do {
                    try fm.moveItem(at: backupURL, to: currentURL) // 롤백
                    return "앱 교체에 실패했습니다 (설치 폴더 권한 확인): \(error.localizedDescription)"
                } catch {
                    return "앱 교체 중 오류가 발생했고 복구도 실패했습니다. 이전 버전이 다음 위치에 있습니다: \(backupURL.path)"
                }
            }

            // 5. 재실행: 분리 프로세스가 1초 후 새 번들을 열고, 현재 앱은 종료
            do {
                let relaunch = Process()
                relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
                relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", currentURL.path]
                try relaunch.run()
            } catch {
                return "업데이트는 완료되었습니다. 앱이 자동으로 재실행되지 않으면 수동으로 실행해 주세요."
            }
            NSApp.terminate(nil)
            return nil // 도달하지 않음
        } catch {
            return "업데이트 실패: \(error.localizedDescription)"
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
                                        "\(path) 종료 코드 \(process.terminationStatus): \(stderr.prefix(200))"])
        }
    }
}
