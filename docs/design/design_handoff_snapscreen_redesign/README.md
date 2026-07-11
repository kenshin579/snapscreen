# Handoff: SnapScreen UI 리디자인 (macOS Tahoe 네이티브 스타일)

## Overview
SnapScreen(macOS 스크린샷 캡처 + 주석 편집 오픈소스 앱)의 홈 창·편집기·설정 창 3개 화면을 최신 macOS 네이티브 스타일로 리디자인한 확정안입니다. 기능 구조는 기존 코드베이스를 그대로 유지합니다(캡처 3종, 주석 도구 9종, 설정 4섹션).

## About the Design Files
`final_design.dc.html`은 **HTML로 만든 디자인 레퍼런스**입니다(프로토타입 아님, 정적 목업). 이 HTML을 그대로 쓰는 것이 아니라, **기존 SwiftUI 코드베이스(SnapScreenKit)에서 재구현**하는 것이 과제입니다. 기존 파일 매핑:

- 홈 → `Sources/SnapScreenKit/Home/HomeView.swift`
- 편집기 툴바 → `Sources/SnapScreenKit/Editor/ToolbarView.swift` (레이아웃이 크게 바뀜: 상단 가로 툴바 → 좌측 세로 레일 + 우측 인스펙터)
- 설정 → `Sources/SnapScreenKit/Settings/SettingsView.swift` (grouped Form → 사이드바 2-pane)
- 도구/색 상태 → `Sources/SnapScreenKit/Editor/EditorState.swift`

가능한 한 시스템 표준(SF Symbols, `.ultraThinMaterial` 등 vibrancy 재질, 시스템 semantic color)을 사용하고, 아래 hex 값은 시스템 색상이 없을 때의 기준값으로 삼으세요.

## Fidelity
**High-fidelity.** 색·타이포·간격·radius를 그대로 재현하는 것이 목표입니다. 단, macOS 시스템 컨트롤(트래픽 라이트, 토글, 슬라이더)은 네이티브 컨트롤을 그대로 사용합니다.

## Screens / Views

디자인 파일 안 화면 ID: 라이트 2a(홈)·2b(편집기)·2c(설정), 다크 2d·2e·2f. 라이트/다크는 동일 구조이며 색 토큰만 다릅니다.

### 1. 홈 창 (2a / 2d) — 폭 440pt
- **titlebar**: 트래픽 라이트 + 중앙 타이틀 "SnapScreen" (13pt semibold). 본문과 같은 배경(인라인 titlebar, `.hiddenTitleBar` + 커스텀).
- **캡처 타일 3개**: 3열 그리드, gap 10. 타일 = radius 14, 패딩 상18/하14.
  - 라이트: bg `rgba(255,255,255,0.72)`, border `rgba(0,0,0,0.06)` 1px, 내부 상단 하이라이트 `inset 0 1px 0 rgba(255,255,255,0.9)`
  - 다크: bg `rgba(255,255,255,0.07)`, border `rgba(255,255,255,0.10)`
  - 내용: SF Symbol 26pt 액센트색(`rectangle.dashed` / `macwindow` / `display`) → 라벨 13pt semibold → 키캡 칩(아래 Design Tokens).
- **최근 캡처**: 섹션 라벨 12pt semibold secondary + 우측 "모두 지우기" 11pt. 썸네일 120×78, radius 10, hairline border. hover 시 우상단 18pt 원형 삭제(✕) 버튼(`rgba(0,0,0,0.55)` bg, 흰 아이콘). 가로 스크롤 + 기존 좌우 화살표 로직 유지.
- **푸터**: 좌측 설정 기어 아이콘(15pt, tertiary) — 설정 창 열기. 우측 버전 `v{x.y.z}` mono 10.5pt tertiary.

### 2. 편집기 (2b / 2e) — 예시 760pt, 창 크기 가변
- **titlebar**: 트래픽 라이트 + 중앙 파일명(12.5pt medium secondary) + 우측: undo·redo 아이콘 버튼(redo 비활성 시 opacity 0.35) → "복사" 버튼(보조 스타일) → "저장" 버튼(액센트 채움, 흰 글자 12pt semibold, radius 8).
- **좌측 도구 레일**: 폭 52pt, 반투명 사이드 재질(라이트 `rgba(255,255,255,0.65)` / 다크 `rgba(28,28,31,0.85)`), 우측 hairline.
  - 도구 버튼 36×32, radius 9, 세로 gap 4. 선택된 도구 = 액센트 배경 + 흰 아이콘. 9개 도구 순서: 화살표, 사각형, 원, 텍스트, 블러, 모자이크, 번호, 펜, 지우개 (기존 `EditorTool` 순서·심볼 그대로).
  - 레일 하단(Spacer 뒤): 자르기(crop), 텍스트 추출(text.viewfinder). 자르기 비활성 조건(주석 존재 시) 유지.
- **캔버스**: 중립 배경(라이트 radial `#E3E6EC→#D3D7DF` / 다크 `#2C3240→#1F2229`), 이미지 중앙 배치 + 그림자.
- **우측 인스펙터**: 폭 170pt, 패딩 14, 섹션 gap 16. 섹션 라벨 11pt semibold secondary.
  - **색상**: 6개 스와치 18pt 원형, 6열 그리드 gap 6. 선택 = 2px 배경색 링 + 3.5px 액센트 링(box-shadow 두 겹).
  - **선 굵기**: 슬라이더 + 현재값 "3px" (11pt, tabular-nums). ※ 신규 상태값
  - **그림자**: 라벨 12pt + 네이티브 토글. ※ 신규 상태값 (주석 도형 그림자 on/off)
  - 구분선 후 **빠른 작업**: "텍스트 추출", "자르기" 리스트 버튼(12pt, radius 8, bg 라이트 `rgba(0,0,0,0.045)` / 다크 `rgba(255,255,255,0.07)`).

### 3. 설정 (2c / 2f) — 620pt, 사이드바 2-pane
- **사이드바**: 폭 190pt, 어두운 사이드 재질(라이트 `rgba(236,236,240,0.9)` / 다크 `rgba(28,28,31,0.9)`), 우측 hairline. 트래픽 라이트 이후 네비 4항목: 단축키·저장·히스토리·정보.
  - 항목 행: 패딩 7×9, radius 8, 아이콘 타일 22pt(radius 6, 각각 #007AFF·#34C759·#8E8E93·#48484A(다크)/#636366(라이트) bg + 흰 SF Symbol 12pt) + 라벨 12.5pt.
  - 선택 항목: 액센트 배경 + 흰 글자.
  - 하단: 버전 mono 10pt tertiary.
- **콘텐츠 페인**: 패딩 18×20. 페이지 타이틀 15pt bold → grouped 카드(radius 12, 라이트: 흰 bg + hairline / 다크: `rgba(255,255,255,0.055)` bg).
  - 카드 행: 패딩 11×13, 행 사이 hairline(left-inset 13).
  - **단축키 recorder 행**: 좌측 라벨 13pt, 우측 키캡 칩들(⇧ ⌘ 4 개별 칩). 녹음 중 행: bg `rgba(액센트,0.08~0.12)` + "녹음 중… 키를 누르세요" 액센트색 11.5pt semibold.
  - 카드 아래 도움말 캡션 11.5pt secondary.
  - 저장/히스토리/정보 페인은 미도안 — 동일한 grouped 카드 패턴으로 기존 SettingsView 항목(저장 폴더, 파일명 접두어, 보관 개수, 버전/업데이트)을 배치하면 됨.

## Interactions & Behavior
- 캡처 타일: hover 시 배경 약간 밝게, press 시 scale 0.98 (표준 buttonStyle 수준).
- 썸네일: hover 시 삭제 버튼 표시(기존 로직 유지), 클릭 시 편집기 열기.
- 도구 레일: 클릭 즉시 선택(라디오), 선택 도구 액센트 채움. 툴팁 = 기존 `EditorTool.label`.
- 단축키 recorder: 클릭 → 녹음 상태(행 하이라이트 + 안내문) → 키 입력 시 키캡으로 표시. KeyboardShortcuts 라이브러리 그대로.
- 복사/저장, undo/redo, 자르기 비활성 규칙 등 동작은 기존 코드 그대로.

## State Management
- 기존: `EditorState.tool`, `EditorState.color`, `AnnotationStore`, `SettingsStore`, `HistoryStore` 유지.
- 신규: `EditorState.lineWidth: CGFloat` (기본 3), `EditorState.shadowEnabled: Bool` (기본 true).
- 설정 창: 선택된 섹션 상태 (`enum SettingsSection: 단축키/저장/히스토리/정보`).

## Design Tokens

### 색상 — 라이트
- 액센트: `#007AFF`
- 창 배경: 홈 `#F7F7F9→#F0F0F3` 그라디언트, 편집기 `#F4F4F6`, 설정 `#F2F2F6`
- 텍스트: primary `#1D1D1F` · secondary `#6E6E73`/`#8E8E93` · tertiary `#AEAEB2`
- hairline/border: `rgba(0,0,0,0.06~0.10)`
- 주석 팔레트: `#FF3B30 #FF9500 #FFCC00 #34C759 #007AFF #1D1D1F`

### 색상 — 다크
- 액센트: `#0A84FF` (어두운 타일 위 아이콘 틴트는 `#409CFF`)
- 창 배경: 홈 `#2C2C30→#232327`, 편집기/설정 `#232326`, 사이드 패널 `rgba(28,28,31,0.85~0.9)`
- 텍스트: primary `#F5F5F7` · secondary `#98989D` · tertiary `#636366`/`#7C7C82`
- hairline/border: `rgba(255,255,255,0.07~0.14)`
- 주석 팔레트: `#FF453A #FF9F0A #FFD60A #30D158 #0A84FF #F5F5F7`

### 키캡 칩 (단축키 표시 공통 컴포넌트)
- mono(SF Mono) 10~11pt semibold, 패딩 2~3 × 5~7, radius 5~6
- border 1px + **bottom 2px** (키캡 입체감)
- 라이트: bg `rgba(0,0,0,0.05)`, border `rgba(0,0,0,0.10)`, 글자 `#3A3A3C`
- 다크: bg `rgba(255,255,255,0.09)`, border `rgba(255,255,255,0.14)`, 글자 `#F5F5F7`

### Radius 스케일
창 12 · 캡처 타일 14 · 카드/그룹 12 · 썸네일 10 · 도구 버튼 9 · 일반 버튼/리스트 버튼 8 · 사이드바 행 8 · 아이콘 타일 6~7 · 키캡 5~6

### 타이포 (SF Pro / 시스템 폰트)
창 타이틀 13 semibold · 페이지 타이틀 15 bold · 본문/행 13 · 버튼 12 (저장 semibold) · 섹션 라벨 11~12 semibold secondary · 캡션 11~11.5 · 버전/단축키 mono

## Assets
별도 이미지 에셋 없음. 아이콘은 전부 SF Symbols 사용:
`rectangle.dashed`, `macwindow`, `display`, `gearshape`, `xmark`, `arrow.up.right`, `rectangle`, `circle`, `textformat`, `drop.halffull`, `mosaic`, `1.circle`, `scribble`, `eraser`, `crop`, `text.viewfinder`, `arrow.uturn.backward`, `arrow.uturn.forward`, `doc.on.doc`, `square.and.arrow.down`, `keyboard`, `folder.fill`, `clock.fill`, `info.circle`.
디자인 HTML 안의 인라인 SVG는 SF Symbols의 플레이스홀더이며, 썸네일의 그라디언트 사각형은 실제 스크린샷 이미지의 플레이스홀더입니다.

## Files
- `final_design.dc.html` — 최종 6개 화면 목업 (2a~2f). 브라우저에서 열어 확인.
- `support.js` — 목업 렌더링용 런타임 (구현과 무관, HTML을 열 때만 필요).
