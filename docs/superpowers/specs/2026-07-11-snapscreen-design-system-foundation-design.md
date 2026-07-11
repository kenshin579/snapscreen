# SnapScreen 디자인 시스템 공통 기반 (Design System Foundation)

작성일: 2026-07-11
상태: 확정 (구현 대기)

## 배경

`docs/design/design_handoff_snapscreen_redesign/`의 확정 리디자인 안(macOS Tahoe 네이티브 스타일)을 기존 SwiftUI 코드베이스에 재구현하는 전체 작업 중 **첫 하위 프로젝트**다.

전체 리디자인은 다음 순서로 분해해 각각 spec → plan → 구현 사이클을 돈다:

1. **공통 기반** (이 문서) — 디자인 토큰 + 키캡 칩 컴포넌트. 나머지 셋이 모두 의존.
2. 홈 리디자인 (`HomeView.swift`)
3. 편집기 리디자인 (`ToolbarView.swift` + `EditorWindowController.swift`) — 상단 가로 툴바 → 좌측 레일 + 우측 인스펙터, 신규 상태(`lineWidth`/`shadowEnabled`)가 렌더러까지 전파
4. 설정 리디자인 (`SettingsView.swift`) — grouped Form → 사이드바 2-pane

이 문서는 (1) 공통 기반만 다룬다.

## 목표

세 화면이 공통으로 의존할 UI 기반을 만든다:

1. 라이트/다크에 자동 반응하는 **디자인 토큰**(색·radius·타이포)
2. 재사용 **키캡 칩** 컴포넌트
3. `KeyboardShortcuts.Shortcut`을 개별 키캡 문자열 배열로 분해하는 **순수 헬퍼**

이 단계는 순수 기반이라 단독으로 화면에 나타나는 산출물이 없다. **완료 기준은 `swift build` 통과 + 단위 테스트 통과**이며, 실질적 육안 검증은 다음 홈 리디자인 단계에서 처음 이뤄진다.

## 비목표

- 주석 팔레트(`PaletteColor`)의 다크 대응 검토 — 편집기 리디자인 단계로 미룬다.
- 애셋 카탈로그(Assets.xcassets) 도입 — 이 프로젝트는 Xcode 프로젝트 파일이 없는 순수 SwiftPM이므로 코드 기반 토큰을 쓴다.
- 실제 화면(홈/편집기/설정) 변경 — 각각 별도 하위 프로젝트.

## 파일 구조

새 폴더 `Sources/SnapScreenKit/DesignSystem/`:

```
DesignSystem/
├── DesignTokens.swift    — 색·radius·타이포 토큰 (동적 라이트/다크 색 포함)
├── KeycapChip.swift      — 키캡 칩 SwiftUI View
└── ShortcutKeycaps.swift — KeyboardShortcut → [String] 분해 (AppKit 비의존 순수 로직 분리)
```

`Support/`가 아닌 별도 폴더로 두는 이유: 홈·편집기·설정이 공통으로 의존하는 UI 기반이라 한 곳에 모으는 게 탐색·유지보수에 유리하다.

## 컴포넌트 설계

### 1. DesignTokens

`enum DesignTokens`(인스턴스 없는 네임스페이스). 커스텀 hex 색은 동적 `NSColor`로 만들어 시스템 다크 모드에 자동 반응하게 한다. 시스템 semantic으로 커버되는 색은 그대로 사용한다.

방침:
- **시스템 semantic 우선.** 텍스트 색은 SwiftUI `.primary`/`.secondary`/`.tertiary`, 액센트는 `Color.accentColor`. hex는 hairline·타일 배경처럼 semantic이 없는 것만 동적 정의.
- 홈/편집기/설정 배경색이 화면마다 다르므로(핸드오프 §Design Tokens) 화면별 배경 토큰을 둔다.

```swift
public enum DesignTokens {
    public enum Colors {
        // 시스템 semantic 사용 (여기서 재정의하지 않음): accent, primary/secondary/tertiary 텍스트
        static let hairline = dynamic(light: rgba(0,0,0,0.08), dark: rgba(255,255,255,0.10))
        static let tileFill = dynamic(light: rgba(255,255,255,0.72), dark: rgba(255,255,255,0.07))
        static let tileBorder = dynamic(light: rgba(0,0,0,0.06), dark: rgba(255,255,255,0.10))
        // 화면별 배경 (홈/편집기/설정), 캔버스 배경 등 — 각 화면 단계에서 소비
        ...
    }
    public enum Radius {
        static let window: CGFloat = 12
        static let tile: CGFloat = 14
        static let card: CGFloat = 12
        static let thumb: CGFloat = 10
        static let tool: CGFloat = 9
        static let button: CGFloat = 8
        static let sidebarRow: CGFloat = 8
        static let iconTile: CGFloat = 7
        static let keycap: CGFloat = 6
    }
    public enum Typography {
        static let windowTitle = Font.system(size: 13, weight: .semibold)
        static let pageTitle = Font.system(size: 15, weight: .bold)
        static let sectionLabel = Font.system(size: 12, weight: .semibold)
        static let body = Font.system(size: 13)
        static let button = Font.system(size: 12)
        static let caption = Font.system(size: 11.5)
        // mono(버전/단축키) 등
    }
    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
```

(정확한 hex 값은 핸드오프 README의 §Design Tokens를 기준으로 채운다. 위 코드는 구조 예시다.)

### 2. KeycapChip

글자 하나짜리 칩. 핸드오프 §키캡 칩 스펙 그대로:
- SF Mono 10~11pt semibold
- 패딩 2~3 × 5~7, radius 6
- border 1px + **bottom 2px**(키캡 입체감)
- 라이트: bg `rgba(0,0,0,0.05)`, border `rgba(0,0,0,0.10)`, 글자 `#3A3A3C`
- 다크: bg `rgba(255,255,255,0.09)`, border `rgba(255,255,255,0.14)`, 글자 `#F5F5F7`

```swift
public struct KeycapChip: View {
    let text: String   // "⌘", "⇧", "1", "A" 등 글자 하나
    public init(_ text: String) { self.text = text }
    public var body: some View { ... }
}
```

하단 2px 입체감은 배경 위에 살짝 겹친 사각형 두 겹, 또는 `.overlay(alignment: .bottom)`으로 하단 라인을 얹어 구현한다.

### 3. ShortcutKeycaps

`KeyboardShortcuts.Shortcut`을 표준 순서 `⌃⌥⇧⌘` + 키 순의 문자열 배열로 분해한다.

- 수식어 정렬·심볼 매핑 등 **순수 로직은 AppKit 비의존 함수로 분리**해 단위 테스트한다 (CLAUDE.md 컨벤션).
- `getShortcut`이 `nil`이면 빈 배열을 반환 → 호출부가 "미설정" 텍스트로 폴백.

```swift
public enum ShortcutKeycaps {
    // AppKit 비의존 순수 코어: 수식어 심볼 집합 + 키 심볼 → 표준순서 배열
    static func order(modifiers: Set<ModifierSymbol>, key: String?) -> [String]
    // 글루: KeyboardShortcuts.Shortcut? → [String]
    public static func decompose(_ shortcut: KeyboardShortcuts.Shortcut?) -> [String]
}
```

**호출부 사용 패턴** (홈 캡처 타일, 설정 recorder 공통):

```swift
HStack(spacing: 3) {
    ForEach(ShortcutKeycaps.decompose(shortcut), id: \.self) { KeycapChip($0) }
}
```

## 테스트

- **단위 테스트** `Tests/SnapScreenKitTests/ShortcutKeycapsTests.swift` — 순수 분해 로직만:
  - `⌘⇧1` → `["⌘", "⇧", "1"]` (표준 순서 재정렬 확인)
  - 수식어 없는 단축키
  - 함수키(F1 등)
  - 미설정(nil) → `[]`
- **DesignTokens / KeycapChip은 UI라 자동 테스트 불가.** `swift build` 통과 + 다음 홈 단계에서 라이트/다크 전환 포함 육안 검증.

## 완료 기준

- `swift build` 성공
- `swift test --filter ShortcutKeycapsTests` 통과
- `DesignSystem/` 3개 파일 생성, 한글 포함 시 UTF-8 확인(`file -I`)
