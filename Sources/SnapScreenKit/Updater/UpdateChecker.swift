import Foundation

public enum UpdateStatus: Equatable {
    case upToDate
    case available(version: String, downloadURL: URL)
    case failed(String)
}

/// GitHub /releases/latest 응답의 필요한 부분만 디코딩
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    let tagName: String
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

public enum UpdateChecker {
    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/kenshin579/snapscreen/releases/latest")!
    public static let releasesPageURL =
        URL(string: "https://github.com/kenshin579/snapscreen/releases")!

    /// 시맨틱 버전 비교. 반환: a<b 음수 / a==b 0 / a>b 양수. 자릿수가 달라도 동작 ("1.0" == "1.0.0")
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// 릴리스 JSON을 해석해 업데이트 상태를 결정한다 (순수 함수 — 단위 테스트 대상)
    public static func status(currentVersion: String, releaseJSON: Data) -> UpdateStatus {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: releaseJSON)
        } catch {
            return .failed("릴리스 정보를 해석하지 못했습니다")
        }
        let latest = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst()) : release.tagName
        guard compareVersions(currentVersion, latest) < 0 else { return .upToDate }
        guard let asset = release.assets.first(where: {
            $0.name.hasPrefix("SnapScreen-") && $0.name.hasSuffix(".zip")
        }) else {
            return .failed("릴리스에 zip 에셋이 없습니다")
        }
        return .available(version: latest, downloadURL: asset.browserDownloadURL)
    }

    /// GitHub API 호출 + 상태 결정
    public static func check(currentVersion: String = AppInfo.version) async -> UpdateStatus {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("업데이트 확인 실패 (HTTP)")
            }
            return status(currentVersion: currentVersion, releaseJSON: data)
        } catch {
            return .failed("업데이트 확인 실패 (네트워크)")
        }
    }
}
