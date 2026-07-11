# 업데이트 메뉴 클릭 시 설정 About 섹션 직행

작성일: 2026-07-12
상태: 확정

## 문제

메뉴바의 "Update available (v…)…" 항목이 일반 `openSettings`를 호출해, 설정 창이 마지막에 보던 섹션(기본 Shortcuts)으로 열린다. 사용자는 Upgrade 버튼이 있는 About(정보) 섹션을 직접 찾아가야 한다.

## 목표 동작

- 업데이트 메뉴 항목 클릭 → 설정 창이 **About 섹션이 선택된 상태로** 열림.
- 일반 "Settings…"/⌘,/홈 기어는 기존대로(마지막 섹션 유지).

## 변경 (4개 파일)

1. **`SettingsView.swift`**: `@State section`을 `SettingsUIState: ObservableObject`(`@Published var section`)로 끌어올려 주입받음(외부 제어 가능). `hovered`는 `@State` 유지.
2. **`SettingsWindowController.swift`**: `uiState` 소유, `SettingsView(ui: uiState, ...)` 주입, `show(section: SettingsSection? = nil)` — 지정 시 전환 후 표시.
3. **`AppDelegate.swift`**: `openSettings(section:)` 헬퍼 추가, 기존 `@objc openSettings(_:)`는 section nil로 위임. `StatusItemController`에 `openSettingsAbout` 클로저 전달.
4. **`StatusItemController.swift`**: 업데이트 메뉴 항목이 새 `@objc openUpdateSettings`(→`openSettingsAbout` 클로저)를 호출.

## 검증

- `swift build`/`swift test` 회귀 없음.
- 설정 창이 지정 섹션으로 열리는 것은 임시 코드 경로로 확인 가능하나, 실제 업데이트 메뉴 경유 확인은 다음 릴리스 사이클에서 가능(현재 앱이 최신이라 메뉴 미노출) — 한계를 PR에 명시.
