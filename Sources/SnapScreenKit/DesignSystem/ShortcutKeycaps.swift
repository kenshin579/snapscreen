import Foundation
import KeyboardShortcuts

/// 단축키를 개별 키캡 문자열 배열로 분해한다.
/// 홈 캡처 타일·설정 recorder에서 `KeycapChip`과 함께 쓴다.
public enum ShortcutKeycaps {
    /// 순수 로직: 단축키 표현 문자열("⌘⇧1")을 grapheme cluster 단위로 쪼갠다.
    /// 결합 문자(키패드 "1⃣", 도움말 "?⃝")는 하나의 Character라 자동으로 한 원소가 된다.
    /// - AppKit/키보드 레이아웃 비의존 → 단위 테스트 대상.
    public static func keycaps(from description: String) -> [String] {
        description.map(String.init)
    }

    /// 글루: 등록된 단축키를 키캡 배열로. 미설정이면 빈 배열.
    /// `Shortcut.description`이 @MainActor(키보드 레이아웃 접근)이라 이 함수도 @MainActor.
    @MainActor
    public static func decompose(_ shortcut: KeyboardShortcuts.Shortcut?) -> [String] {
        guard let shortcut else { return [] }
        return keycaps(from: shortcut.description)
    }
}
