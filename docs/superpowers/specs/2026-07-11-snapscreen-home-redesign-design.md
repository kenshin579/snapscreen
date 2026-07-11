# SnapScreen 홈 창 리디자인 (Home Redesign)

작성일: 2026-07-11
상태: 확정 (구현 대기)

## 배경

`docs/design/design_handoff_snapscreen_redesign/`의 확정 리디자인 안(macOS Tahoe 네이티브 스타일)을 기존 SwiftUI 코드베이스에 재구현하는 전체 작업 중 **두 번째 하위 프로젝트**다. 첫 번째(디자인 시스템 공통 기반: `DesignTokens`·`KeycapChip`·`ShortcutKeycaps`)는 PR #28로 main에 병합 완료.

전체 분해: 공통 기반(완료) → **홈(이 문서)** → 편집기 → 설정.

디자인 원안: 핸드오프 README `§1. 홈 창 (2a / 2d)`.

## 목표

기존 홈 창(`HomeView` + `HomeWindowController`)을 확정 디자인에 맞춰 재구현한다. **기존 기능·동작(캡처 3종, 최근 캡처 스크롤·화살표·hover 삭제, 히스토리 열기)은 그대로 유지**하고 시각·창 구조만 바꾼다. 공통 기반의 `DesignTokens`·`KeycapChip`·`ShortcutKeycaps`가 홈에서 처음 실제로 소비되며, 라이트/다크 전환을 실제 앱 실행으로 육안 검증한다.

## 비목표

- 편집기·설정 리디자인 (각각 별도 하위 프로젝트).
- 캡처/히스토리/스크롤 **로직** 변경 — 스타일·레이아웃만 손댄다.
- 주석 팔레트(`PaletteColor`) 다크 대응 — 편집기 단계.

## 변경 대상 파일

- **Modify** `Sources/SnapScreenKit/Home/HomeWindowController.swift` — 인라인 투명 타이틀바, `.fullSizeContentView`, `onOpenSettings` 파라미터 추가, 폭 440.
- **Modify** `Sources/SnapScreenKit/Home/HomeView.swift` — 타이틀 영역, 캡처 타일 재스타일, 키캡 칩, 최근 캡처 스타일, 푸터 설정 기어.
- **Modify** `Sources/SnapScreenKit/AppCore/AppDelegate.swift` — `HomeWindowController` 생성부에 `onOpenSettings` 클로저 전달.
- **Modify** `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift` — 홈 화면 고유 색 토큰 추가.

## 설계

### 1. 창 / 타이틀바 (`HomeWindowController`)

- `styleMask`에 `.fullSizeContentView` 추가 (기존 `.titled, .closable, .miniaturizable` 유지, 리사이즈 불가 유지).
- `window.titlebarAppearsTransparent = true`, `window.titleVisibility = .hidden`.
- 트래픽 라이트(닫기/최소화)는 시스템 것을 그대로 유지 — 접근성·표준 유지.
- `onOpenSettings: @escaping @MainActor () -> Void` 파라미터를 `init`에 추가하고 `HomeView`에 전달.
- 콘텐츠가 타이틀바 아래까지 확장되므로 창 배경은 SwiftUI 콘텐츠 배경(홈 그라디언트)이 채운다.

### 2. 콜백 배선 (`AppDelegate`)

`HomeWindowController(...)` 생성부(현재 line 29~42)에 다음 인자 추가:
```swift
onOpenSettings: { [weak self] in self?.openSettings(nil) }
```
`openSettings(_:)`는 이미 존재하므로 재사용한다.

### 3. HomeView 레이아웃

폭 440. 위에서 아래로:
1. **타이틀 영역** — 트래픽 라이트 높이(약 28pt)를 비우는 상단 영역에 "SnapScreen" 13pt semibold(`DesignTokens.Typography.windowTitle`) 중앙 정렬.
2. **캡처 타일 3개** — 3열 `HStack`, gap 10.
3. `Divider`.
4. **최근 캡처** 섹션.
5. **푸터**.

### 4. 캡처 타일

기존 `items` 배열·`onCapture(item.mode)` 로직 유지, 스타일만 교체:
- 각 타일 radius 14(`DesignTokens.Radius.tile`), 패딩 상18/하14.
- 배경 `DesignTokens.Colors.tileFill`, 테두리 `DesignTokens.Colors.tileBorder` 1px.
- **내부 상단 하이라이트**: 타일 상단 1px 밝은 라인(`DesignTokens.Colors.tileTopHighlight` — 라이트 흰색 90% / 다크 흰색 8%), 라운드 클립 안쪽에 `.overlay(alignment: .top)`.
- 내용(세로 스택): SF Symbol **26pt** `DesignTokens.Colors.accentIconTint` 색 → 라벨 13pt semibold → 단축키.
- **단축키 표시**:
  ```swift
  let keys = ShortcutKeycaps.decompose(KeyboardShortcuts.getShortcut(for: item.shortcutName))
  if keys.isEmpty {
      Text("미설정").font(.system(size: 11)).foregroundStyle(.tertiary)
  } else {
      HStack(spacing: 3) { ForEach(keys, id: \.self) { KeycapChip($0) } }
  }
  ```
- 상호작용: hover 시 배경 약간 밝게, press 시 scale 0.98 (표준 `buttonStyle` 수준). 기존 `.accessibilityLabel`/`.accessibilityHint` 유지.

### 5. 최근 캡처

기존 `capturesScroller`·`scrollBy`·`leadingID`·화살표·hover 삭제 로직 전부 유지, 스타일만:
- 섹션 라벨 "최근 캡처" 12pt semibold secondary + 우측 "모두 지우기" 11pt (기존 유지).
- 썸네일 120×78, radius **10**(`DesignTokens.Radius.thumb`, 기존 8), 테두리 `DesignTokens.Colors.hairline`.
- hover 삭제 버튼: 우상단 **18pt 원형**, 배경 `DesignTokens.Colors.thumbDeleteButtonBackground`(`rgba(0,0,0,0.55)` 고정), 흰 ✕ 아이콘.
- 빈 상태 "아직 캡처가 없습니다" 유지.

### 6. 푸터

`HStack`:
- **좌측: 설정 기어** — `gearshape` 15pt tertiary, 버튼 → `onOpenSettings()` (신규).
- 우측: 버전 `v{AppInfo.version}` `DesignTokens.Typography.mono`(10.5pt) tertiary.

### 7. DesignTokens 추가

`DesignTokens.Colors`에:
- `homeBackgroundTop` / `homeBackgroundBottom` — 라이트 `#F7F7F9`/`#F0F0F3`, 다크 `#2C2C30`/`#232327` (홈 창 배경 그라디언트).
- `tileTopHighlight` — 라이트 흰색 90% / 다크 흰색 8%.
- `thumbDeleteButtonBackground` — `rgba(0,0,0,0.55)` (고정, 흰 아이콘 대비용).

## 테스트 / 검증

- `swift build` 성공, `swift test` 기존 88개 회귀 없음 (홈 변경이 로직에 영향 없음 확인).
- **실제 앱 실행 육안 검증** (`Scripts/run.sh`) — 홈은 UI라 자동 테스트 불가, 이 하위 프로젝트의 실질 검증 지점:
  1. 라이트/다크 전환 시 배경·타일·텍스트 색이 의도대로 반응
  2. 캡처 타일 3개 렌더 + 키캡 칩(단축키 설정 시) / "미설정" 폴백(미설정 시)
  3. 최근 캡처 썸네일·hover 삭제 버튼·좌우 화살표 동작
  4. 푸터 기어 클릭 → 설정 창 열림
  5. 인라인 타이틀바(트래픽 라이트 + 중앙 "SnapScreen" 타이틀, 본문과 같은 배경)
  6. 캡처 3종·히스토리 열기 등 기존 동작 회귀 없음
- 한글 포함 소스 UTF-8 확인 (`file -I`).

## 완료 기준

- 위 파일 4개 수정, `swift build`/`swift test` 통과.
- 실제 앱 실행 육안 검증 6개 항목 확인.
- 기존 기능 회귀 없음.
