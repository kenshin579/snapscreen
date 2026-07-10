# 최근 캡처 슬라이드 좌우 화살표 설계 문서

- 날짜: 2026-07-10
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.10.2

## 1. 배경

가로 슬라이드(v0.10.1)는 좌우로 더 볼 캡처가 있어도 스크롤 가능하다는 시각 신호가 없다. 스크롤 위치에 따라 양쪽 끝에 `‹`/`›` 화살표를 띄워 "더 있음"을 알리고, 클릭하면 그 방향으로 넘겨보게 한다(트랙패드/휠 없이도 탐색).

## 2. 범위

- 최근 캡처 가로 스크롤의 **왼쪽 끝이 아니면 `‹`**, **오른쪽 끝이 아니면 `›`** 반투명 화살표 오버레이 표시
- 화살표 **클릭 시 그 방향으로 한 뷰포트만큼 스크롤**(근접 항목으로 부드럽게 이동)
- 스크롤 위치가 끝에 닿으면 해당 방향 화살표 자동 숨김
- 항목이 뷰포트에 다 들어오면(스크롤 불필요) 화살표 없음

**비목표**: 세로 스크롤 화살표, 자동 스크롤/캐러셀, 페이지 인디케이터(점), 키보드 화살표 네비게이션.

## 3. 변경 사항

`Sources/SnapScreenKit/Home/HomeView.swift`의 최근 캡처 섹션만 수정. 모델·클릭·삭제는 그대로.

- 가로 `ScrollView`를 `ScrollViewReader`로 감싸고 `ZStack`으로 좌우 화살표 오버레이를 얹는다
- **스크롤 오프셋 추적**: 스크롤 콘텐츠에 `GeometryReader` + `PreferenceKey`(`ScrollOffsetKey`, HomeView.swift 내 private)로 현재 가로 오프셋을 `@State scrollOffset`에 반영. 뷰포트 너비는 바깥 `GeometryReader`로 측정해 `@State viewportWidth`에 저장
- **콘텐츠 너비**: 항목 스트라이드(썸네일 120 + 간격 10 = 130) × 개수 − 10으로 계산(`contentWidth`)
- **화살표 표시 조건**:
  - 왼쪽(`‹`): `scrollOffset > 2`
  - 오른쪽(`›`): `scrollOffset < contentWidth - viewportWidth - 2`
- **클릭 스크롤**: `ScrollViewReader`의 proxy로, 현재 왼쪽 첫 항목 인덱스(`round(scrollOffset / 130)`) 기준 ±(뷰포트에 들어가는 항목 수)만큼 떨어진 항목 `id`로 `scrollTo(anchor: .leading)`, `withAnimation`
- 화살표 모양: `chevron.left`/`chevron.right` SF Symbol, 반투명 원형 배경(대비 위해 흰 심볼 + 어두운 반투명 배경), 세로 중앙 정렬, 스크롤 영역 양 끝에 겹치게

## 4. 에러 처리 / 엣지

- 항목 0개/1개 또는 전부 뷰포트에 들어옴: `contentWidth ≤ viewportWidth`라 양쪽 조건 모두 거짓 → 화살표 없음
- 클릭 시 목표 인덱스가 범위를 벗어나면 `clamp`(0…count−1)
- 삭제로 항목이 줄어 스크롤 위치가 콘텐츠를 벗어나면: 다음 `onPreferenceChange`에서 오프셋 재평가(SwiftUI가 콘텐츠에 맞춰 클램프) → 화살표 상태 자동 갱신

## 5. 테스트

- SwiftUI 레이아웃/스크롤이라 자동 테스트 없음(로직·모델 변경 없음) → 기존 78개 회귀 없음 확인
- **수동**: `docs/manual-test-checklist.md` §19에 "캡처가 많아 스크롤될 때 좌우에 화살표가 나타나고, 끝에 닿으면 해당 화살표가 사라지며, 클릭하면 그 방향으로 넘어간다" 항목 추가

## 6. 버전

v0.10.2 — `AppInfo.version` "0.10.2", `Info.plist` `CFBundleShortVersionString` "0.10.2", `CFBundleVersion` 18.
