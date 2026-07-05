import AppKit

/// 표시 중인 앱 창 수에 따라 독 아이콘을 토글한다.
/// 등록 창이 0이면 .accessory(독 숨김·메뉴바 상주), 1개 이상이면 .regular(독 표시·포커스 정상).
@MainActor
public final class ActivationPolicyManager {
    private var registered: Set<ObjectIdentifier> = []
    private let applyPolicy: @MainActor (NSApplication.ActivationPolicy) -> Void

    public init(applyPolicy: @MainActor @escaping (NSApplication.ActivationPolicy) -> Void
                = { NSApp.setActivationPolicy($0) }) {
        self.applyPolicy = applyPolicy
    }

    /// 등록 창 수 → 정책 (순수 함수 — 단위 테스트 대상)
    public static func policy(forWindowCount count: Int) -> NSApplication.ActivationPolicy {
        count > 0 ? .regular : .accessory
    }

    public var count: Int { registered.count }

    public func register(_ token: ObjectIdentifier) {
        registered.insert(token)
        applyPolicy(Self.policy(forWindowCount: registered.count))
    }

    public func unregister(_ token: ObjectIdentifier) {
        registered.remove(token)
        applyPolicy(Self.policy(forWindowCount: registered.count))
    }

    // 편의: NSWindow ↔ 토큰
    public func register(_ window: NSWindow) { register(ObjectIdentifier(window)) }
    public func unregister(_ window: NSWindow) { unregister(ObjectIdentifier(window)) }
}
