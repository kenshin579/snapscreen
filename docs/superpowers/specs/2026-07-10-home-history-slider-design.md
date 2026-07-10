# 홈 창 최근 캡처 가로 슬라이드 설계 문서

- 날짜: 2026-07-10
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.10.1

## 1. 배경

최근 캡처 갤러리(v0.10.0)는 세로 그리드(`LazyVGrid`)를 고정 높이 260pt로 표시한다. 항목이 2개뿐이어도 그 높이를 차지해 창 아래에 큰 빈 공간이 남는다(사용자 스크린샷으로 확인). 최근 캡처를 **가로 한 줄 슬라이드**로 바꿔 세로 공간을 항목 수와 무관하게 최소화하고, 많아지면 좌우 스크롤로 넘겨보게 한다.

## 2. 범위

- `HomeView`의 "최근 캡처" 섹션을 세로 그리드 → **가로 스크롤(`ScrollView(.horizontal)` + `LazyHStack`)** 로 변경
- 썸네일 고정 크기 **가로 120 × 세로 78**, 한 줄 배치
- 섹션 높이를 썸네일 한 줄로 고정 → 항목이 2개든 50개든 세로 공간 동일(빈 공간 제거). 창은 SwiftUI 내용 크기에 맞춰 세로가 줄어든다(리사이즈 불가 유지)
- 비었을 때 플레이스홀더도 같은 낮은 높이로 컴팩트하게
- **유지**: 썸네일 클릭 → 편집기 재열기, 우클릭 → 삭제, 날짜 툴팁(`.help`)

**비목표**: 썸네일 크기 조절 UI, 세로/가로 전환 옵션, 페이지네이션, 모델·저장·삭제 로직 변경(그대로 재사용).

## 3. 변경 사항

`Sources/SnapScreenKit/Home/HomeView.swift`의 body 중 "최근 캡처" 블록만 수정:

- 기존:
  - 비었을 때 `Text("아직 캡처가 없습니다")`를 `minHeight: 120`으로
  - 아니면 `ScrollView { LazyVGrid(columns: adaptive) { ... } }.frame(height: 260)`
- 변경 후:
  - 공통으로 **낮은 고정 높이**(썸네일 78 + 여백 ≈ 86pt) 영역
  - 비었을 때 같은 높이에 플레이스홀더
  - 아니면 `ScrollView(.horizontal, showsIndicators: false) { LazyHStack(spacing: 10) { ForEach(entries) { thumbnail($0) } } }`
- `thumbnail(_:)`은 프레임을 `width: 120, height: 78`로 고정(기존 `height: 78` + `maxWidth: .infinity` → 고정 width). 클릭/컨텍스트메뉴/`.help`는 그대로

`columns` 상수(`GridItem`)는 더 이상 쓰지 않으므로 제거.

## 4. 에러 처리 / 엣지

- 항목 0개: 컴팩트 플레이스홀더(레이아웃만, 로직 무관)
- 항목 다수(최대 50): 가로 스크롤로 처리, 성능은 `LazyHStack`이 보이는 셀만 로드
- 썸네일 로드 실패: 기존 플레이스홀더(`photo` 심볼) 유지

## 5. 테스트

- 모델·저장·클릭·삭제 로직은 변경 없음 → 기존 78개 단위 테스트가 회귀 없음을 보장(레이아웃만 변경)
- **수동**: `docs/manual-test-checklist.md` §19에 "최근 캡처가 가로 한 줄로 표시되고, 많으면 좌우 스크롤되며, 창 세로에 큰 빈 공간이 없다" 항목 보강

## 6. 버전

v0.10.1 — `AppInfo.version` "0.10.1", `Info.plist` `CFBundleShortVersionString` "0.10.1", `CFBundleVersion` 17.
