# SnapScreen 설계 문서

- 날짜: 2026-07-03
- 상태: 승인됨 (브레인스토밍 완료)

## 1. 개요

macOS용 오픈소스 스크린샷 캡처 + 주석 편집 앱. 유료 앱(CleanShot X, Shottr Pro)의 핵심 기능을 무료 오픈소스로 제공한다.

**목표 (MVP)**
- 전체 화면 / 창 / 영역 캡처 (전역 단축키)
- 캡처 직후 주석 편집기 자동 실행 (화살표, 사각형/원, 텍스트, 블러, 스텝 배지)
- 클립보드 복사 / 파일 저장
- 메뉴바 상주 앱 (독 아이콘 없음)

**비목표 (MVP 제외, v2 후보)**
- 핀 투 스크린, OCR — Apple Vision으로 v2에서 우선 추가 예정
- 스크롤 캡처, 캡처 직후 플로팅 썸네일, 화면 녹화(동영상/GIF)
- 클라우드 업로드, 코드 서명/공증, Homebrew cask, Sparkle 자동 업데이트

## 2. 배경 조사 요약

**시장**: 성공한 macOS 캡처 앱은 유료(CleanShot X, Shottr)든 오픈소스(macshot, Snapzy, BetterShot, Capso — 모두 2025~26년 등장)든 예외 없이 Swift + ScreenCaptureKit. 크로스플랫폼 스택은 실패 사례가 뚜렷함(Electron 기반 Kap은 동면, Qt 기반 Flameshot은 서명 문제로 Homebrew 퇴출 예정).

**기술 스택 결정**: Go + Wails v3는 "조건부 가능"으로 판정 — 시스트레이·전역 단축키·투명 오버레이는 내장돼 있으나, ① v3가 알파 상태, ② macOS Wails 스크린샷 앱 선례 전무, ③ 캡처·이미지 클립보드·Retina 처리에 cgo(ObjC) 필수라 Go의 장점이 소멸. **Swift 네이티브(AppKit 코어 + SwiftUI UI)로 결정** — 검증된 구성이고, CLI 빌드 파이프라인이 AI 주도 개발과 궁합이 좋으며, Claude로 개발된 선례(macshot)도 있음.

## 3. 아키텍처

- **타깃**: macOS 14 (Sonoma) 이상 — `SCScreenshotManager`가 macOS 14+ 요구
- **프로젝트**: SwiftPM 기반, Xcode 프로젝트 파일 없음. `swift build` + 스크립트로 .app 번들 조립
- **UI 구성 원칙**: 정밀 이벤트 처리가 필요한 곳(캡처 오버레이, 주석 캔버스, 메뉴바)은 AppKit, 폼 UI(설정, 편집기 툴바)는 SwiftUI

**모듈 5개**

| 모듈 | 책임 |
|---|---|
| AppCore | NSStatusItem 메뉴바 상주, `ActivationPolicy.accessory`(독 숨김), 전역 단축키, 앱 수명주기 |
| CaptureKit | ScreenCaptureKit 래퍼: 전체/창/영역 캡처, TCC 권한 처리 |
| SelectionOverlay | 영역 선택 UI: 디스플레이별 투명 풀스크린 패널, 십자선 + 치수 표시, 창 하이라이트 |
| Editor | 주석 편집기 창: 도구 5종, 실행취소/재실행, 내보내기 |
| Settings | 설정 창(SwiftUI): 단축키, 저장 폴더, 파일명 형식 |

**사용자 흐름**

```
전역 단축키 (기본: cmd+shift+1 영역 / cmd+shift+2 창 / cmd+shift+3 전체)
  → 영역 선택 / 창 선택 / 전체 캡처
  → 주석 편집기 창이 바로 열림 (Shottr 방식)
  → 편집 후 cmd+C 클립보드 복사 또는 cmd+S 파일 저장
```

## 4. 캡처 파이프라인

**권한 (TCC)**
- 캡처 전 `CGPreflightScreenCaptureAccess()`로 화면 기록 권한 확인. 없으면 안내 다이얼로그 → `x-apple.systempreferences:` URL로 시스템 설정의 해당 패널 열기 → 권한 부여 후 앱 재시작 필요 안내
- macOS 15+의 월간 재승인 프롬프트는 시스템 동작이므로 수용
- 개발 중에도 항상 .app 번들로 빌드해 실행 (터미널 직접 실행 시 TCC 권한이 터미널에 귀속되는 문제 방지 — 빌드 스크립트가 처리)

**캡처 흐름**

```
단축키 → HotkeyManager → CaptureCoordinator
  영역: SelectionOverlay 표시 → 드래그 → 선택 rect 반환
  창:   SelectionOverlay(창 모드) → SCShareableContent 창 목록 →
        마우스 아래 창 하이라이트 → 클릭 확정
  전체: 현재 마우스가 있는 디스플레이
→ CaptureKit: SCScreenshotManager.captureImage(filter:configuration:)
→ CGImage (Retina 픽셀 해상도 유지)
→ Editor 창 열림
```

**SelectionOverlay 세부**
- 디스플레이마다 borderless `NSPanel` 1개, 윈도우 레벨 `.screenSaver`, 모든 Spaces 표시
- 배경 반투명 어둡게, 선택 영역만 밝게; 십자선 커서 + 좌표/크기(px) 라벨; `esc` 취소
- 드래그는 시작한 디스플레이 안으로 제한 (디스플레이 걸침 선택은 MVP 제외)
- 돋보기(확대경)는 MVP 제외
- 이미지는 항상 픽셀 단위(Retina 2x)로 유지, PNG 저장 시 DPI 메타데이터 포함

**출력**
- 클립보드: `NSPasteboard`에 PNG
- 파일 저장 기본 위치: **시스템 스크린샷 저장 위치(`defaults read com.apple.screencapture location`)를 읽어 사용**, 값이 없으면 `~/Desktop`. 앱 설정에서 오버라이드 가능 (오버라이드하지 않으면 시스템 설정을 계속 따름)
- 파일명: `snapscreen 2026-07-03 14.30.15.png` 형식 (설정에서 변경 가능)

## 5. 주석 편집기

**구성**: 상단 툴바(SwiftUI) + 캔버스(AppKit `NSView` 커스텀 뷰)

**비파괴 벡터 모델**
- 원본 캡처 이미지는 불변, 주석은 벡터 객체 배열(`[Annotation]`)로 관리
- 화면 표시 = 원본 + 주석 순서대로 렌더링; 내보내기 시점에만 flatten
- 주석 선택 → 이동/수정/삭제 가능, undo/redo는 배열 조작

**도구 5종** (단축키 1키)

| 도구 | 키 | 동작 |
|---|---|---|
| 화살표 | `A` | 드래그 시작→끝, 굵기·색 조절 |
| 사각형/원 | `R` / `O` | 드래그, 테두리만 |
| 텍스트 | `T` | 클릭 위치 입력, 크기·색 조절 |
| 블러 | `B` | 드래그 영역 픽셀레이트 (원본 기준 렌더링) |
| 스텝 배지 | `N` | 클릭마다 ①②③ 자동 증가 |

- 공통: 클릭 선택 → 드래그 이동, `delete` 삭제, 색상 팔레트(빨강 기본 + 5~6색), `cmd+Z` / `cmd+shift+Z`
- **블러는 강한 픽셀레이트(모자이크)로 구현** — 약한 가우시안 블러는 복원 공격 가능하므로 민감정보 가리기 용도에 부적합
- 내보내기: `cmd+C` 클립보드, `cmd+S` 저장. 창 닫으면 경고 없이 폐기 (캡처 재시도 마찰 최소화)

## 6. 에러 처리

| 상황 | 처리 |
|---|---|
| 화면 기록 권한 없음 | 안내 창 + "시스템 설정 열기" 버튼, 재시작 필요 안내 |
| 캡처 실패 (SCK 오류) | 알림 배너로 사유 표시, 앱은 계속 동작 |
| 저장 실패 (폴더 없음/권한) | `~/Desktop` 폴백 저장 + 알림 고지 |
| 단축키 등록 충돌 | 앱은 기동, 설정 창에 충돌 표시 + 변경 유도 |

## 7. 테스트 전략

- **단위 테스트 (`swift test`)**: 주석 모델(추가/이동/삭제/undo), 좌표 변환(포인트↔픽셀, 디스플레이 좌표계), 파일명 생성, 시스템 저장 위치 읽기 — 로직 계층은 UI 없이 테스트 가능하게 분리
- **수동 테스트 체크리스트** (릴리스 전, 문서로 관리): TCC 권한 플로우, 멀티 모니터, Retina 해상도, 클립보드 붙여넣기 — 화면 캡처·권한은 자동화 불가

## 8. 배포

- 라이선스: **MIT**
- GitHub Actions: 태그 푸시 시 .app 빌드 → zip → Release 업로드
- 초기 미서명 배포, README에 `xattr -cr` 안내. Developer ID 서명/공증($99/년)은 사용자 증가 시 재검토

## 9. 저장소 구조

```
snapscreen/
├── Package.swift
├── Sources/SnapScreen/   # AppCore, CaptureKit, SelectionOverlay, Editor, Settings
├── Tests/
├── Scripts/              # .app 번들 조립, 로컬 실행
└── docs/
```
