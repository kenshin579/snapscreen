# 최근 캡처 호버 삭제 버튼 설계 문서

- 날짜: 2026-07-10
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.10.4

## 1. 배경

최근 캡처 항목 삭제가 현재 우클릭 컨텍스트 메뉴로만 가능해 발견성이 낮다. 썸네일에 마우스를 올리면 우상단에 X 버튼을 띄워, 삭제 방법을 바로 알 수 있게 한다.

## 2. 범위

- 썸네일에 **호버 시 우상단 X 버튼** 표시 → 클릭하면 그 캡처 **즉시 삭제**(확인 다이얼로그 없음)
- 마우스가 벗어나면 X 버튼 숨김
- 기존 **우클릭 컨텍스트 메뉴 삭제 제거**(X 버튼으로 일원화)
- 썸네일 본체 클릭(편집기 열기)과 X 버튼 클릭이 겹치지 않게 분리

**비목표**: 삭제 확인 다이얼로그, 다중 선택 삭제, 전체 비우기, 삭제 애니메이션(SwiftUI 기본 전이로 충분).

## 3. 변경 사항

`Sources/SnapScreenKit/Home/HomeView.swift`의 `thumbnail(_:)`만 수정. 모델·저장·클릭 재편집은 그대로.

- `@State private var hoveredID: UUID?` 추가(어느 썸네일에 호버 중인지)
- `thumbnail(_:)`을 `Button{...}.contextMenu{...}` 구조에서 **`ZStack(alignment: .topTrailing)`** 으로 재구성:
  - 바닥: 기존 이미지 `Button { onOpenEntry(entry) }`(편집기 열기)
  - 위: `hoveredID == entry.id`일 때만 X `Button { history.remove(id: entry.id) }` (반투명 어두운 원 + 흰 `xmark`, 우상단에 약간의 여백)
  - ZStack 전체에 `.onHover { hoveredID = $0 ? entry.id : (hoveredID == entry.id ? nil : hoveredID) }`
- 기존 `.contextMenu { Button("삭제"...) }` 제거
- `.help(날짜)`는 유지

두 Button은 ZStack 형제(중첩 아님)라 히트 영역이 분리된다. X 버튼(작은 우상단)이 위에 있어 그 영역 클릭은 삭제, 나머지는 편집기 열기.

## 4. 에러 처리 / 엣지

- 삭제는 기존 `history.remove(id:)` 재사용(파일+메타 삭제, 부가 기능이라 실패해도 조용). 즉시 반영
- 삭제로 항목이 사라지면 `hoveredID`가 없는 id를 가리킬 수 있으나, 조건이 `hoveredID == entry.id`라 렌더에 무해(다음 호버에 갱신)
- 스크롤 중 호버: SwiftUI가 `.onHover`를 관리, 문제 없음

## 5. 테스트

- SwiftUI 레이아웃/호버라 자동 테스트 없음(모델 무변경) → 기존 78개 회귀 없음 확인
- **수동**: `docs/manual-test-checklist.md` §19에 "썸네일에 마우스를 올리면 우상단 X가 나타나고, 클릭하면 즉시 삭제된다. 썸네일 본체 클릭은 편집기 열기로 동작한다" 항목 추가

## 6. 버전

v0.10.4 — `AppInfo.version` "0.10.4", `Info.plist` `CFBundleShortVersionString` "0.10.4", `CFBundleVersion` 20.
