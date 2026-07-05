import XCTest
import AppKit
@testable import SnapScreenKit

@MainActor
final class ActivationPolicyManagerTests: XCTestCase {
    private final class Dummy {}

    func testPolicyForWindowCount() {
        XCTAssertEqual(ActivationPolicyManager.policy(forWindowCount: 0), .accessory)
        XCTAssertEqual(ActivationPolicyManager.policy(forWindowCount: 1), .regular)
        XCTAssertEqual(ActivationPolicyManager.policy(forWindowCount: 5), .regular)
    }

    func testRegisterUnregisterDrivesPolicy() {
        var applied: [NSApplication.ActivationPolicy] = []
        let mgr = ActivationPolicyManager(applyPolicy: { applied.append($0) })
        // Dummy 인스턴스를 변수로 유지해야 한다 — ObjectIdentifier(Dummy())처럼 인라인으로 쓰면
        // 임시 객체가 구문 종료 직후 즉시 해제되어, 다음 Dummy() 할당이 같은 메모리를 재사용하며
        // 서로 다른 두 식별자가 우연히 동일해지는(포인터 재사용) 문제가 발생한다.
        let dummyA = Dummy()
        let dummyB = Dummy()
        let a = ObjectIdentifier(dummyA)
        let b = ObjectIdentifier(dummyB)

        mgr.register(a)                       // 0→1: regular
        mgr.register(b)                       // 1→2: regular
        mgr.unregister(a)                     // 2→1: regular
        mgr.unregister(b)                     // 1→0: accessory
        XCTAssertEqual(applied, [.regular, .regular, .regular, .accessory])
        XCTAssertEqual(mgr.count, 0)
    }

    func testDuplicateRegisterIgnored() {
        var applied: [NSApplication.ActivationPolicy] = []
        let mgr = ActivationPolicyManager(applyPolicy: { applied.append($0) })
        let a = ObjectIdentifier(Dummy())
        mgr.register(a)
        mgr.register(a)                       // 중복 — 집합 크기 그대로
        XCTAssertEqual(mgr.count, 1)
        mgr.unregister(a)
        mgr.unregister(a)                     // 없는 것 해제 — 안전
        XCTAssertEqual(mgr.count, 0)
    }
}
