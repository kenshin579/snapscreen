import XCTest
@testable import SnapScreenKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: 버전 비교

    func testCompareVersions() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.0", "0.1.0"), 0)
        XCTAssertLessThan(UpdateChecker.compareVersions("0.1.0", "0.2.0"), 0)
        XCTAssertGreaterThan(UpdateChecker.compareVersions("1.0.0", "0.9.9"), 0)
        XCTAssertLessThan(UpdateChecker.compareVersions("0.2.0", "0.10.0"), 0)  // 숫자 비교 (문자열 비교 아님)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0", "1.0.0"), 0)        // 자릿수 상이
        XCTAssertGreaterThan(UpdateChecker.compareVersions("1.0.1", "1.0"), 0)
    }

    // MARK: 릴리스 JSON 해석

    private func releaseJSON(tag: String, assetNames: [String]) -> Data {
        let assets = assetNames.map {
            #"{"name": "\#($0)", "browser_download_url": "https://github.com/kenshin579/snapscreen/releases/download/\#(tag)/\#($0)"}"#
        }.joined(separator: ",")
        return #"{"tag_name": "\#(tag)", "assets": [\#(assets)]}"#.data(using: .utf8)!
    }

    func testStatusAvailableWhenNewerVersion() {
        let json = releaseJSON(tag: "v0.2.0", assetNames: ["SnapScreen-v0.2.0.zip"])
        let status = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json)
        guard case .available(let version, let url) = status else {
            return XCTFail("expected .available, got \(status)")
        }
        XCTAssertEqual(version, "0.2.0")
        XCTAssertTrue(url.absoluteString.hasSuffix("SnapScreen-v0.2.0.zip"))
    }

    func testStatusUpToDateWhenSameVersion() {
        let json = releaseJSON(tag: "v0.1.0", assetNames: ["SnapScreen-v0.1.0.zip"])
        XCTAssertEqual(UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json), .upToDate)
    }

    func testStatusUpToDateWhenCurrentIsNewer() {
        // 개발 빌드가 릴리스보다 앞서는 경우 다운그레이드 제안 금지
        let json = releaseJSON(tag: "v0.1.0", assetNames: ["SnapScreen-v0.1.0.zip"])
        XCTAssertEqual(UpdateChecker.status(currentVersion: "0.9.0", releaseJSON: json), .upToDate)
    }

    func testStatusSelectsZipAsset() {
        let json = releaseJSON(tag: "v0.2.0",
                               assetNames: ["checksums.txt", "SnapScreen-v0.2.0.zip"])
        guard case .available(_, let url) = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json) else {
            return XCTFail("expected .available")
        }
        XCTAssertTrue(url.absoluteString.hasSuffix(".zip"))
    }

    func testStatusFailsWhenNoZipAsset() {
        let json = releaseJSON(tag: "v0.2.0", assetNames: ["checksums.txt"])
        guard case .failed = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json) else {
            return XCTFail("expected .failed")
        }
    }

    func testStatusFailsOnMalformedJSON() {
        let status = UpdateChecker.status(currentVersion: "0.1.0",
                                          releaseJSON: Data("not json".utf8))
        guard case .failed = status else { return XCTFail("expected .failed") }
    }

    func testTagWithoutVPrefix() {
        let json = releaseJSON(tag: "0.2.0", assetNames: ["SnapScreen-0.2.0.zip"])
        guard case .available(let version, _) = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json) else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(version, "0.2.0")
    }
}
