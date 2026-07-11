# SnapScreen 설정 리디자인 (Settings Redesign)

작성일: 2026-07-12
상태: 확정 (구현 대기)

## 배경

macOS Tahoe 네이티브 스타일 리디자인 전체 중 **마지막(네 번째) 하위 프로젝트**. 공통 기반(PR #28)·홈(PR #29)·편집기(PR #30) 병합 완료.

디자인 원안: 핸드오프 README `§3. 설정 (2c / 2f)`. 저장/히스토리/정보 페인은 미도안 — 동일 카드 패턴으로 기존 항목을 배치한다(핸드오프 명시).

## 목표

설정 창을 grouped `Form`에서 **사이드바 2-pane**(190pt 사이드바 + 카드 기반 콘텐츠, 620pt 창, 인라인 투명 타이틀바)으로 재구성한다. **기존 기능·동작(단축키 녹음, 저장 폴더 변경/기본값, 파일명 접두어, 보관 개수, 버전/업데이트 확인/업그레이드)은 전부 유지**하고 시각·구조만 바꾼다.

## 비목표

- 다국어 지원(별도 과제로 보류 — UI 문자열 한국어 유지).
- 커스텀 단축키 recorder — **네이티브 `KeyboardShortcuts.Recorder` 유지** (핵심 결정, 아래 참조).
- 설정 항목 추가/제거.

## 핵심 설계 결정 (브레인스토밍 확정)

1. **recorder는 네이티브 유지**: `KeyboardShortcuts` 라이브러리의 녹음 안전 로직(녹음 중 전역 단축키 일시정지 `isPaused`, 시스템 예약 검사 `isTakenBySystem`, 금지 조합 검사)이 전부 internal이라 커스텀 재구현 시 포기해야 함(예: ⌘⇧1 재녹음 중 캡처 오발동 위험). 핸드오프의 키캡 칩 recorder 행은 "시스템 컨트롤은 네이티브 그대로" 방침의 연장으로 네이티브 컨트롤을 스타일된 카드 행(좌 라벨 13pt + 우 Recorder)에 배치하는 것으로 대체한다.
2. **창 구조**: 홈과 동일한 인라인 투명 타이틀바 패턴(`.fullSizeContentView` + `titlebarAppearsTransparent` + `titleVisibility = .hidden`) — 트래픽 라이트가 사이드바 위에 얹히는 System Settings 스타일. 폭 620 고정, 높이 고정(~430), 리사이즈 불가 유지.
3. **레이아웃**: `HStack(spacing: 0)` — 사이드바 190pt 고정 + 콘텐츠 페인. `NavigationSplitView`는 고정 크기 창에 과함.

## 변경 대상 파일

- **Modify** `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift` — `settingsSidebar`, `settingsCard` 색 토큰 추가.
- **Rewrite** `Sources/SnapScreenKit/Settings/SettingsView.swift` — 셸(HStack) + `SettingsSection` enum + 사이드바.
- **Create** `Sources/SnapScreenKit/Settings/SettingsCard.swift` — grouped 카드/행/캡션 공용 컴포넌트.
- **Create** `Sources/SnapScreenKit/Settings/SettingsPanes.swift` — 4개 페인 뷰(기존 폴더 선택·업데이트/업그레이드 로직 이동, 동작 무변경).
- **Modify** `Sources/SnapScreenKit/Settings/SettingsWindowController.swift` — 인라인 타이틀바 styleMask.

## 설계

### 1. 상태

```swift
enum SettingsSection: CaseIterable {
    case shortcuts, saving, history, about   // 단축키 / 저장 / 히스토리 / 정보
}
```
`SettingsView`에 `@State private var section: SettingsSection = .shortcuts`.

### 2. 사이드바 (190pt)

- 배경 `DesignTokens.Colors.settingsSidebar` — 라이트 `rgba(236,236,240,0.9)` / 다크 `rgba(28,28,31,0.9)`, 우측 hairline.
- 상단 트래픽 라이트 높이(~40pt) 비움 → 네비 4항목:

| 섹션 | SF Symbol | 아이콘 타일 배경 |
|---|---|---|
| 단축키 | `keyboard` | `#007AFF` |
| 저장 | `folder.fill` | `#34C759` |
| 히스토리 | `clock.fill` | `#8E8E93` |
| 정보 | `info.circle` | 라이트 `#636366` / 다크 `#48484A` |

- 항목 행: 패딩 7×9, radius 8(`Radius.sidebarRow`), 아이콘 타일 22pt(radius 6~7 `Radius.iconTile`, 흰 SF Symbol 12pt) + 라벨 12.5pt. 선택 = 액센트 배경 + 흰 글자, 비선택 hover 시 옅은 배경.
- 하단(`Spacer` 뒤): 버전 `v{AppInfo.version}` mono 10pt tertiary.

### 3. 콘텐츠 페인 & 카드 패턴 (`SettingsCard`)

- 페인 패딩 18×20, 페이지 타이틀 15pt bold(`Typography.pageTitle`).
- 카드: radius 12(`Radius.card`), 라이트 흰 bg + hairline / 다크 `rgba(255,255,255,0.055)`(`DesignTokens.Colors.settingsCard`).
- 카드 행: 패딩 11×13, 행 사이 hairline(좌측 인셋 13).
- 카드 아래 도움말 캡션 11.5pt secondary(`Typography.caption`).

### 4. 페인 내용 (`SettingsPanes`) — 기존 기능 그대로 재배치

- **단축키**: recorder 행 3개 — 좌 라벨 13pt("영역 캡처" 등) + 우 네이티브 `KeyboardShortcuts.Recorder`.
- **저장**: 저장 폴더 행(현재 경로 표시 + "변경…" + override 시 "기본값") / 파일명 접두어 행(TextField). `pickFolder()`(NSOpenPanel) 로직 이동.
- **히스토리**: 보관 개수 행 — 기존 Picker([20,50,100,200]).
- **정보**: 버전 행 / 업데이트 행(기존 `updateStatusText` 상태별 표시 + "업데이트 확인"/"업그레이드"/"다운로드 중…" 버튼, `upgrade()` NSAlert 로직 이동, 동작 무변경).

### 5. 창 (`SettingsWindowController`)

- `styleMask = [.titled, .closable, .fullSizeContentView]`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `isReleasedWhenClosed = false` 유지.
- `window.title = "SnapScreen 설정"` 유지(Mission Control/VoiceOver용, 화면 표시는 숨김).
- show()/windowWillClose의 policyManager 등록/해제 유지.

## 테스트 / 검증

- `swift build` + `swift test`(88개 — 설정은 UI라 신규 테스트 없음, `SettingsStoreTests` 회귀 확인).
- 실행 스모크(`Scripts/run.sh`) — 설정 창은 캡처(TCC) 없이 홈 기어로 바로 열 수 있어 검증 용이.
- **육안 검증(사용자)**: 사이드바 4항목 전환, recorder 재녹음(시스템 예약 검사·오발동 방지 동작 포함), 폴더 변경/기본값, 접두어 입력, 보관 개수, 업데이트 확인, 라이트/다크, 인라인 타이틀바.
- 한글 소스 UTF-8.

## 완료 기준

- 위 파일 5개 수정/신설, `swift build`/`swift test` 통과.
- 실행 스모크 + 육안 검증.
- 기존 설정 동작 회귀 없음.

## 다음 단계

이 하위 프로젝트로 리디자인 4부작(공통 기반 → 홈 → 편집기 → 설정)이 완결된다. 이후 후보: 다국어 지원(보류 과제), `docs/manual-test-checklist.md` 갱신 및 릴리스.
