import XCTest
@testable import SnapScreenKit

private struct FakeSystemLocation: SystemLocationReading {
    let value: String?
    func screencaptureLocation() -> String? { value }
}

final class SaveLocationResolverTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testOverrideWins() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: "/tmp"))
        XCTAssertEqual(r.resolve(override: tempDir.path), tempDir.standardizedFileURL)
    }

    func testSystemLocationUsedWhenNoOverride() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: tempDir.path))
        XCTAssertEqual(r.resolve(override: nil), tempDir.standardizedFileURL)
    }

    func testFallsBackToDesktopWhenSystemValueMissing() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: nil))
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
        XCTAssertEqual(r.resolve(override: nil), desktop)
    }

    func testFallsBackWhenDirectoryDoesNotExist() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: "/nonexistent/dir"))
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
        XCTAssertEqual(r.resolve(override: "/also/nonexistent"), desktop)
    }

    func testTildeExpansion() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: "~/Desktop"))
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
        XCTAssertEqual(r.resolve(override: nil), desktop)
    }
}
