import XCTest
@testable import SnapScreenKit

final class LocalizationTests: XCTestCase {
    private func stringsDict(_ locale: String) throws -> [String: String] {
        // Tests/SnapScreenKitTests/LocalizationTests.swift → 패키지 루트
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SnapScreenKit/Resources/\(locale).lproj/Localizable.strings")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                                 "\(locale).lproj/Localizable.strings 파싱 실패: \(url.path)")
        return dict
    }

    /// en/ko 키 집합이 완전히 일치해야 한다 — 한쪽만 추가하면 번역 누락.
    func testKeySetsMatch() throws {
        let en = try stringsDict("en"), ko = try stringsDict("ko")
        let onlyEN = Set(en.keys).subtracting(ko.keys)
        let onlyKO = Set(ko.keys).subtracting(en.keys)
        XCTAssertTrue(onlyEN.isEmpty, "ko.lproj에 누락된 키: \(onlyEN.sorted())")
        XCTAssertTrue(onlyKO.isEmpty, "en.lproj에 누락된 키: \(onlyKO.sorted())")
    }

    /// 모든 값이 비어있지 않아야 한다.
    func testNoEmptyValues() throws {
        for locale in ["en", "ko"] {
            for (key, value) in try stringsDict(locale) {
                XCTAssertFalse(value.isEmpty, "\(locale).lproj의 빈 값: \(key)")
            }
        }
    }

    /// L() 헬퍼가 모듈 번들에서 실제로 조회하는지 (시드 키).
    func testHelperResolvesFromModuleBundle() {
        XCTAssertFalse(L("Copy").isEmpty)
    }
}
