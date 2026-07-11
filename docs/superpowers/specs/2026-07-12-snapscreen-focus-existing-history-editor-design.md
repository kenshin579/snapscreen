# 히스토리 편집기 중복 창 방지 (Focus Existing History Editor)

작성일: 2026-07-12
상태: 확정

## 배경 / 문제

홈의 최근 캡처 썸네일을 같은 항목으로 여러 번 클릭하면 클릭 수만큼 편집기 창이 열린다. `CaptureCoordinator.openFromHistory(image:scale:)`가 어느 히스토리 항목인지 모른 채 매번 새 `EditorWindowController`를 만들기 때문.

## 목표 동작

- 같은 히스토리 항목의 편집기가 이미 열려 있으면 **새 창 대신 기존 창을 앞으로 가져와 포커스**.
- 창을 닫은 뒤 다시 클릭하면 새로 열림 (기존 onClose 정리 로직이 배열에서 제거하므로 자동).
- 새 캡처(히스토리 클릭이 아닌 경로)는 기존대로 항상 새 창 (`historyEntryID = nil`).

## 변경 (3개 파일, 소규모)

1. **`EditorWindowController`**: `public let historyEntryID: UUID?` 추가, init 파라미터(기본 nil).
2. **`CaptureCoordinator`**: `openFromHistory(image:scale:entryID:)`로 확장 —
   `editors`에서 같은 `historyEntryID`를 찾으면 `makeKeyAndOrderFront` + `NSApp.activate` 후 반환, 없으면 entryID를 넣어 생성. `openEditor`에 entryID 파라미터(기본 nil) 추가.
3. **`AppDelegate`**: `onOpenEntry`에서 `entry.id` 전달.

## 검증

- `swift build` / `swift test` 회귀 없음 (UI 동작이라 신규 단위 테스트 없음).
- 실사용: 같은 썸네일 2회 클릭 → 창 1개 포커스 / 닫고 재클릭 → 새로 열림 / 다른 썸네일 → 별도 창 / 새 캡처 → 항상 새 창.
