# 디자인 시스템 공통 기반 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈·편집기·설정 리디자인이 공통으로 의존할 디자인 토큰·키캡 칩·단축키 분해 헬퍼를 `Sources/SnapScreenKit/DesignSystem/`에 만든다.

**Architecture:** 순수 SwiftPM(애셋 카탈로그 없음)이므로 코드 기반 동적 라이트/다크 색을 쓴다. 단축키 분해는 `Shortcut.description`(이미 표준 순서 `⌃⌥⇧⌘`+키 문자열)을 grapheme cluster 단위로 쪼개는 순수 함수 + `@MainActor` 글루로 분리해, 순수 부분만 단위 테스트한다.

**Tech Stack:** Swift, SwiftUI, AppKit(NSColor 동적 색), KeyboardShortcuts 패키지, XCTest.

**참고 스펙:** `docs/superpowers/specs/2026-07-11-snapscreen-design-system-foundation-design.md`
**디자인 값 출처:** `docs/design/design_handoff_snapscreen_redesign/README.md` §Design Tokens

---

## File Structure

- **Create** `Sources/SnapScreenKit/DesignSystem/ShortcutKeycaps.swift` — 단축키 → 키캡 문자열 배열 분해. 순수 함수 `keycaps(from:)` + `@MainActor decompose(_:)`.
- **Create** `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift` — 색(동적 라이트/다크)·radius·타이포 토큰 + 색 헬퍼(`NSColor(hex:)`, `dynamic(light:dark:)`).
- **Create** `Sources/SnapScreenKit/DesignSystem/KeycapChip.swift` — 글자 하나짜리 키캡 칩 SwiftUI View. DesignTokens 소비.
- **Create** `Tests/SnapScreenKitTests/ShortcutKeycapsTests.swift` — `keycaps(from:)` 순수 로직 단위 테스트.

작업 순서는 (1) 독립·테스트 가능한 ShortcutKeycaps → (2) DesignTokens → (3) DesignTokens에 의존하는 KeycapChip 순으로, 검증 가능한 순수 로직을 먼저 완성한다.

---

## Task 1: ShortcutKeycaps (단축키 분해, TDD)

**Files:**
- Create: `Sources/SnapScreenKit/DesignSystem/ShortcutKeycaps.swift`
- Test: `Tests/SnapScreenKitTests/ShortcutKeycapsTests.swift`

**배경:** `KeyboardShortcuts.Shortcut.description`는 `"⌘⇧1"`처럼 수식어를 표준 순서(⌃⌥⇧⌘)로 붙이고 마지막에 키 심볼을 붙인 완성 문자열이다. 이걸 grapheme cluster(Swift `Character`) 단위로 쪼개면 `["⌘","⇧","1"]`이 된다. 키패드 키(`"1⃣"` = `1`+U+20E3 결합 문자)나 도움말(`"?⃝"`)도 하나의 grapheme cluster라 `Character` 분해가 정확히 처리한다. 순수 부분(문자열→배열)만 테스트하고, `.description` 접근(`@MainActor`, 키보드 레이아웃 의존)은 글루로 분리한다.

- [ ] **Step 1: Write the failing test**

`Tests/SnapScreenKitTests/ShortcutKeycapsTests.swift`:

```swift
import XCTest
@testable import SnapScreenKit

final class ShortcutKeycapsTests: XCTestCase {
    func testModifiersAndKeySplitIntoIndividualKeycaps() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "⌘⇧1"), ["⌘", "⇧", "1"])
    }

    func testSingleModifierWithLetter() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "⌘A"), ["⌘", "A"])
    }

    func testNoModifierSingleKey() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "F2"), ["F", "2"])
    }

    func testEmptyStringReturnsEmptyArray() {
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: ""), [])
    }

    func testCombiningKeycapStaysSingleElement() {
        // 키패드 1 = "1" + U+20E3(결합 enclosing keycap) → 하나의 grapheme cluster
        XCTAssertEqual(ShortcutKeycaps.keycaps(from: "⌘1\u{20E3}"), ["⌘", "1\u{20E3}"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShortcutKeycapsTests`
Expected: 컴파일 실패 — "cannot find 'ShortcutKeycaps' in scope"

- [ ] **Step 3: Write minimal implementation**

`Sources/SnapScreenKit/DesignSystem/ShortcutKeycaps.swift`:

```swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ShortcutKeycapsTests`
Expected: 5개 테스트 모두 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SnapScreenKit/DesignSystem/ShortcutKeycaps.swift Tests/SnapScreenKitTests/ShortcutKeycapsTests.swift
git commit -m "feat: 단축키를 개별 키캡 문자열로 분해하는 ShortcutKeycaps 추가"
```

---

## Task 2: DesignTokens (색·radius·타이포 토큰)

**Files:**
- Create: `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift`

**배경:** 텍스트 색은 시스템 semantic(SwiftUI `.primary/.secondary/.tertiary`), 액센트는 `Color.accentColor`를 그대로 쓰고, semantic이 없는 hairline·타일·키캡 색만 동적 `NSColor`로 정의한다. Radius·Typography는 핸드오프 값 그대로. 화면 고유 배경(홈 그라디언트, 편집기 캔버스, 설정 사이드바 재질)은 소비 시점(각 화면 단계)에 추가하므로 여기서는 넣지 않는다(YAGNI — 이 단계엔 소비자가 없어 검증 불가).

- [ ] **Step 1: DesignTokens.swift 작성**

`Sources/SnapScreenKit/DesignSystem/DesignTokens.swift`:

```swift
import SwiftUI
import AppKit

public enum DesignTokens {

    // MARK: - Colors
    /// 시스템 semantic이 없는 커스텀 색만 정의한다.
    /// 텍스트(primary/secondary/tertiary)·액센트는 SwiftUI semantic을 직접 쓴다.
    public enum Colors {
        /// hairline/border — 라이트 검정 8%, 다크 흰색 10%
        public static let hairline = dynamic(
            light: NSColor(white: 0, alpha: 0.08),
            dark: NSColor(white: 1, alpha: 0.10))

        /// 캡처 타일 배경 — 라이트 흰색 72%, 다크 흰색 7%
        public static let tileFill = dynamic(
            light: NSColor(white: 1, alpha: 0.72),
            dark: NSColor(white: 1, alpha: 0.07))

        /// 캡처 타일 테두리 — 라이트 검정 6%, 다크 흰색 10%
        public static let tileBorder = dynamic(
            light: NSColor(white: 0, alpha: 0.06),
            dark: NSColor(white: 1, alpha: 0.10))

        /// 어두운 타일 위 아이콘 액센트 틴트 — 라이트는 시스템 액센트, 다크는 #409CFF
        public static let accentIconTint = dynamic(
            light: NSColor(hex: 0x007AFF),
            dark: NSColor(hex: 0x409CFF))

        // MARK: 키캡 칩 (KeycapChip 소비)
        public static let keycapFill = dynamic(
            light: NSColor(white: 0, alpha: 0.05),
            dark: NSColor(white: 1, alpha: 0.09))
        public static let keycapBorder = dynamic(
            light: NSColor(white: 0, alpha: 0.10),
            dark: NSColor(white: 1, alpha: 0.14))
        public static let keycapText = dynamic(
            light: NSColor(hex: 0x3A3A3C),
            dark: NSColor(hex: 0xF5F5F7))
    }

    // MARK: - Radius
    public enum Radius {
        public static let window: CGFloat = 12
        public static let tile: CGFloat = 14
        public static let card: CGFloat = 12
        public static let thumb: CGFloat = 10
        public static let tool: CGFloat = 9
        public static let button: CGFloat = 8
        public static let sidebarRow: CGFloat = 8
        public static let iconTile: CGFloat = 7
        public static let keycap: CGFloat = 6
    }

    // MARK: - Typography
    public enum Typography {
        public static let windowTitle = Font.system(size: 13, weight: .semibold)
        public static let pageTitle = Font.system(size: 15, weight: .bold)
        public static let sectionLabel = Font.system(size: 12, weight: .semibold)
        public static let body = Font.system(size: 13)
        public static let button = Font.system(size: 12)
        public static let buttonProminent = Font.system(size: 12, weight: .semibold)
        public static let caption = Font.system(size: 11.5)
        public static let keycap = Font.system(size: 10.5, weight: .semibold, design: .monospaced)
        public static let mono = Font.system(size: 10.5, design: .monospaced)
    }

    // MARK: - Helpers
    /// 시스템 외관(aqua/darkAqua)에 따라 라이트/다크 색을 자동 선택하는 동적 색.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    /// 0xRRGGBB 형태의 정수로 sRGB 색 생성.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
```

- [ ] **Step 2: 빌드 검증**

Run: `swift build`
Expected: 빌드 성공 (경고 없음). 이 단계는 UI 토큰이라 자동 테스트 대상이 없다.

- [ ] **Step 3: Commit**

```bash
git add Sources/SnapScreenKit/DesignSystem/DesignTokens.swift
git commit -m "feat: 동적 라이트/다크 디자인 토큰(색·radius·타이포) 추가"
```

---

## Task 3: KeycapChip (키캡 칩 View)

**Files:**
- Create: `Sources/SnapScreenKit/DesignSystem/KeycapChip.swift`

**배경:** 글자 하나짜리 칩. SF Mono semibold, radius 6, 1px 테두리 + 하단 2px 바(키캡 입체감). 색은 `DesignTokens.Colors.keycap*` 소비. 하단 2px는 둥근 사각형으로 클립한 뒤 하단 정렬 오버레이 바로 구현한다.

- [ ] **Step 1: KeycapChip.swift 작성**

`Sources/SnapScreenKit/DesignSystem/KeycapChip.swift`:

```swift
import SwiftUI

/// 단축키 표시용 키캡 칩. 글자 하나(예: "⌘", "⇧", "1")를 받는다.
/// 여러 칩은 호출부에서 `ShortcutKeycaps.decompose(...)` 결과를 `ForEach`로 나열해 조합한다.
public struct KeycapChip: View {
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(DesignTokens.Typography.keycap)
            .foregroundStyle(DesignTokens.Colors.keycapText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(DesignTokens.Colors.keycapFill)
            // 하단 2px 바 — 키캡 입체감
            .overlay(alignment: .bottom) {
                DesignTokens.Colors.keycapBorder
                    .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap))
            // 1px 전체 테두리
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap)
                    .strokeBorder(DesignTokens.Colors.keycapBorder, lineWidth: 1))
    }
}

#Preview {
    HStack(spacing: 3) {
        KeycapChip("⌘")
        KeycapChip("⇧")
        KeycapChip("1")
    }
    .padding()
}
```

- [ ] **Step 2: 빌드 검증**

Run: `swift build`
Expected: 빌드 성공. KeycapChip은 UI라 자동 테스트 대상이 없다 — 실제 육안 검증은 홈 리디자인 단계에서 이뤄진다.

- [ ] **Step 3: 전체 테스트 회귀 확인**

Run: `swift test`
Expected: 기존 테스트 + `ShortcutKeycapsTests` 전부 PASS (디자인 시스템 추가가 기존 코드에 영향 없음 확인).

- [ ] **Step 4: Commit**

```bash
git add Sources/SnapScreenKit/DesignSystem/KeycapChip.swift
git commit -m "feat: 키캡 칩 컴포넌트 KeycapChip 추가"
```

---

## 완료 기준 (스펙 대조)

- [x] `DesignSystem/` 3개 파일 생성 (Task 1~3)
- [x] 동적 라이트/다크 색 + radius + 타이포 토큰 (Task 2)
- [x] 키캡 칩 컴포넌트 (Task 3)
- [x] 단축키 분해 순수 헬퍼 + 단위 테스트 (Task 1)
- [ ] `swift build` 성공 — 각 Task에서 확인
- [ ] `swift test` 전체 통과 — Task 3 Step 3
- [ ] 한글 포함 소스 UTF-8 확인: `file -I Sources/SnapScreenKit/DesignSystem/*.swift`

## 다음 단계

이 기반 위에서 **홈 리디자인**이 첫 실제 소비자가 된다. `DesignTokens`·`KeycapChip`·`ShortcutKeycaps`를 홈에서 처음 렌더하며 라이트/다크 전환을 육안 검증한다. 홈 단계에서 화면 고유 배경 토큰(홈 그라디언트 등)을 `DesignTokens.Colors`에 추가한다.
