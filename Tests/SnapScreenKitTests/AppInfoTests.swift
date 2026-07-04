import XCTest
@testable import SnapScreenKit

final class AppInfoTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(AppInfo.version.isEmpty)
    }
}
