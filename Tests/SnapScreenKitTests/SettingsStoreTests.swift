import XCTest
@testable import SnapScreenKit

final class SettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        return d
    }

    func testHistoryLimitDefaultsTo50() {
        let store = SettingsStore(defaults: makeDefaults())
        store.load()
        XCTAssertEqual(store.historyLimit, 50)
    }

    func testHistoryLimitPersistsAndReloads() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.load()
        store.historyLimit = 100

        let reloaded = SettingsStore(defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.historyLimit, 100)
    }
}
