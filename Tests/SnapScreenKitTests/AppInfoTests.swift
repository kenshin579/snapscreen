import XCTest
@testable import SnapScreenKit

final class AppInfoTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(AppInfo.version.isEmpty)
    }

    /// 버전은 AppInfo.version과 Resources/Info.plist 두 곳에 존재한다.
    /// 한쪽만 범프하면 릴리스 zip의 plist 버전이 어긋나 인앱 업데이트 검증
    /// (UpdateInstaller의 CFBundleShortVersionString 비교)이 실패한다 — v0.12.0에서 실제 발생.
    /// 이 테스트는 두 곳이 항상 일치하도록 강제한다.
    func testInfoPlistVersionMatchesAppInfo() throws {
        // Tests/SnapScreenKitTests/AppInfoTests.swift → 패키지 루트 → Resources/Info.plist
        let plistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // SnapScreenKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // 패키지 루트
            .appendingPathComponent("Resources/Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: plistURL),
                                  "Resources/Info.plist를 읽지 못했습니다: \(plistURL.path)")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, AppInfo.version,
                       "Info.plist의 CFBundleShortVersionString이 AppInfo.version과 다릅니다 — 두 곳을 함께 범프하세요")
    }
}
