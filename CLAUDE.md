# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

SnapScreen — macOS 14+ 메뉴바 상주 스크린샷 캡처 + 주석 편집 앱. Swift(AppKit + SwiftUI), SwiftPM 기반이며 **Xcode 프로젝트 파일이 없다** — 전 과정이 CLI로 동작한다. UI 문자열은 한국어.

설계 문서: `docs/superpowers/specs/2026-07-03-snapscreen-design.md` (MVP 범위/비목표 포함)

## 명령어

```bash
swift build                          # 빌드
swift test                           # 전체 테스트
swift test --filter FileSaverTests   # 특정 테스트 클래스만
Scripts/bundle.sh [debug|release]    # swift build + .app 번들 조립 + ad-hoc 서명 → build/SnapScreen.app
Scripts/run.sh                       # bundle.sh 후 기존 인스턴스 종료(pkill) + 실행
Scripts/make-icon.sh                 # AppIcon.svg → Resources/AppIcon.icns 재생성
```

**캡처 동작 확인은 반드시 `Scripts/run.sh`로 실행하라.** `swift run`으로 실행하면 화면 기록 권한(TCC)이 앱이 아닌 터미널에 귀속되고, 번들 없이는 `UNUserNotificationCenter`가 크래시한다. ad-hoc 서명 특성상 코드가 바뀌면 cdhash가 달라져 화면 기록 권한을 시스템 설정에서 다시 켜야 할 수 있다 (중복 SnapScreen 항목은 수동 삭제).

릴리스: `git tag v* && git push origin v*` → `.github/workflows/release.yml`이 zip을 빌드해 GitHub Release 생성.

## 아키텍처

실행 파일 `Sources/SnapScreen/main.swift`는 부트스트랩 몇 줄뿐이고, 모든 코드는 `Sources/SnapScreenKit/` 라이브러리에 있다:

- **AppCore/** — `AppDelegate`, `StatusItemController`(메뉴바), `Hotkeys`(KeyboardShortcuts 패키지, ⌘⇧1/2/0), `CaptureCoordinator`(중앙 오케스트레이터), `MainMenuBuilder`, `ActivationPolicyManager`(아래 활성화 정책 참조)
- **CaptureKit/** — `CaptureEngine`(ScreenCaptureKit `SCScreenshotManager` 래퍼), `ScreenCapturePermission`(TCC preflight)
- **SelectionOverlay/** — 영역 드래그 선택(`SelectionOverlayController`), 창 클릭 선택(`WindowPickerController`). 디스플레이마다 borderless NSPanel 1개
- **Editor/** — 주석 편집기. 데이터 계층(`Annotation`/`AnnotationStore`/`AnnotationHitTester`)은 **AppKit 비의존**, UI 계층(`CanvasView`/`EditorWindowController`/`ToolbarView`)과 분리. crop은 주석/도구가 아닌 CanvasView의 별도 모드다. `ImageCropper`(순수 함수)가 좌하단→좌상단 좌표 변환 후 자르며, 확정 시 EditorWindowController가 이미지를 교체하고 창을 리사이즈한다. crop 버튼 비활성을 위해 `AnnotationStore`는 `ObservableObject`다. 펜 도구는 `AnnotationKind.path`로 드래그 중 찍힌 raw 점열을 그대로 저장하고, 렌더 시에만 `PathSmoother`가 이차 베지어 중점 스무딩으로 곡선화한다. 입력 수집은 `CanvasView.penPoints`에 드래그 포인트를 누적하는 방식. 지우개는 `PathEraser`(순수 함수)가 펜 획(path)에서 커서 반경 안 점을 제거해 조각으로 분할하고 그 외 주석(사각형/화살표/텍스트/번호 배지 등)은 커서가 닿으면 통째로 삭제하며, 한 번의 드래그 동안 지워진 결과를 `AnnotationStore.replace`로 모아 undo 1회로 커밋한다. 원형 커서는 trackingArea/mouseMoved로 CanvasView 위에 그려진다. OCR은 `TextRecognizer`(Vision `VNRecognizeTextRequest`, 온디바이스, 한/영)가 현재 이미지(crop 반영, 주석 미포함)를 인식해 `ClipboardWriter.write(text:)`로 클립보드에 복사하며, 관찰 결과를 위→아래 줄 순서로 정렬·결합하는 로직만 AppKit/Vision 비의존 순수 함수로 분리해 테스트한다.
- **Output/** — PNG 인코딩(DPI 메타), 클립보드(PNG+TIFF 동시 선언), 파일 저장(위치 결정/충돌 회피/Desktop 폴백)
- **Updater/** — 인앱 업데이트. `UpdateChecker`(GitHub API+버전 비교, AppKit 비의존), `UpdateState`(공유 상태), `UpdateInstaller`(다운로드→번들 교체→재실행). 릴리스 zip 에셋 이름 규약 `SnapScreen-vX.Y.Z.zip`을 바꾸면 구버전 업데이터가 깨진다
- **Home/** — 홈 창(`HomeView` 캡처 버튼 3개 + `HomeWindowController`). 앱 실행 시 자동 표시.
- **History/** — 최근 캡처 히스토리. `HistoryArchive`(동기 파일 IO, AppKit 비의존)가 `~/Library/Application Support/SnapScreen/History`에 원본+썸네일+index.json으로 자가 치유 저장하고, `HistoryStore`(@MainActor)가 최근 50개로 롤링하며 캡처를 백그라운드로 저장한다. 캡처마다 자동 기록되며, 홈 창 갤러리에서 썸네일을 클릭하면 `CaptureCoordinator.openFromHistory`가 원본 스케일을 보존해 편집기로 다시 연다.
- **Settings/**, **Support/** — 설정 저장·UI, 좌표 유틸·알림

앱 아이콘은 `Resources/AppIcon.svg`가 소스이며, `Scripts/make-icon.sh`가 이를 iconset을 거쳐 `Resources/AppIcon.icns`로 만들고 `Scripts/bundle.sh`가 이 `.icns`를 번들에 복사한다 (ad-hoc 서명 이전 단계).

**전체 흐름**: 전역 단축키 → `CaptureCoordinator.beginCapture(mode)` → (영역/창이면 오버레이로 선택) → `CaptureEngine` → `CaptureResult{image, scale}` → `handleCaptured`가 `EditorWindowController` 열기 → 사용자가 ⌘C(클립보드)/⌘S(저장).

### 좌표계 규약 (가장 중요한 크로스 파일 지식)

세 좌표계가 공존하며 변환이 틀리면 캡처가 엉뚱한 곳을 찍는다:

1. **Cocoa 전역 좌표** — 원점 좌하단 (`NSScreen.frame`, `NSEvent.mouseLocation`)
2. **CG/SCK 좌표** — 디스플레이 로컬, 원점 좌상단, 포인트 (`SCStreamConfiguration.sourceRect`, `SCWindow.frame`은 CG 전역)
3. **이미지 픽셀 좌표** — 원점 좌하단, 픽셀. **모든 Annotation은 이 좌표계로 저장**

변환은 `Support/ScreenGeometry.swift`(단위 테스트 있음)와 `WindowPickerController.begin()`(CG 전역→Cocoa)에 있다. `CanvasView`는 aspect-fit + 레터박스 오프셋(`fitScale`/`fitOffset`)으로 뷰↔이미지 픽셀을 변환한다.

### 스케일 스레딩

`CaptureResult.scale`(Retina 배율)이 끝까지 흘러야 한다: `CanvasView.captureScale` → 주석 기본 크기(3/16/14 × scale) → `AnnotationRenderer.draw(..., scale:)`(픽셀레이트 블록 크기 `12*scale` 바닥값 — 보안 요구) → `FlattenRenderer.flatten(..., scale:)` → `PNGEncoder`(DPI 메타데이터).

### 주석 렌더링 이원화

`AnnotationRenderer`는 캔버스 실시간 표시(`CanvasView.draw`)와 내보내기(`FlattenRenderer.flatten`) **양쪽에서 공용**이다. 렌더링을 바꾸면 두 경로 모두 영향받는다. 픽셀레이트는 annotation UUID 키 캐시(`pixelateCache`, 64 엔트리 상한)를 쓴다.

## 코드베이스 컨벤션

- **모든 UI 클래스는 `@MainActor`** — `FlattenRenderer`/`AnnotationRenderer`도 포함 (NSGraphicsContext/AppKit 드로잉 때문)
- **모든 NSWindow/NSPanel에 `isReleasedWhenClosed = false`** — 누락 시 close에서 크래시/누수
- **오버레이 패널의 esc는 패널 레벨 `cancelOperation(_:)` 오버라이드로 처리** — view의 keyDown만으로는 first responder 문제로 동작 보장이 안 됨
- **활성화 정책**: `ActivationPolicyManager`가 등록된 표시 창 수를 추적 — 0이면 `.accessory`(독 숨김), 1개 이상이면 `.regular`(독 표시). 홈·편집기·설정 창이 생성/닫힘 시 register/unregister(반드시 `windowWillClose`에서 unregister — 좀비 토큰 방지). `AppDelegate`는 더 이상 시작 시 `.accessory`를 직접 설정하지 않는다.
- **메인 메뉴는 nil-target 문자열 셀렉터** (`MainMenuBuilder`: `saveImage:`/`undoAction:`/`redoAction:`/`copyMerged:`는 `EditorWindowController`, `openSettings:`(⌘,)는 `AppDelegate`의 `@objc` 메서드) — 철자와 **정확히 일치해야 하며 오타는 무음 실패**한다. 앱 전역 액션(`openSettings:`)은 응답 체인 끝 `AppDelegate`(`NSApp.delegate`)에 도달한다. `saveDocument:`는 NSDocument와 충돌하므로 쓰지 말 것
- **코디네이터의 중복 실행 방지는 await 앞에서 동기적으로** — `.window` 케이스의 `isPickingWindow` 플래그 패턴 참조 (guard와 할당 사이에 await가 끼면 레이스)
- 에러 표시: 하드 실패는 `Notifier.alertFailure`(beep+알림), 소프트 안내는 `Notifier.show`
- 로직(Annotation 모델, 저장 위치, 좌표 변환, 파일명)은 AppKit 비의존으로 유지해 `Tests/SnapScreenKitTests/`에서 단위 테스트한다. UI/캡처/TCC는 자동화 불가 — `docs/manual-test-checklist.md`(릴리스 전 실기기 체크리스트)로 검증한다
- 한글 포함 파일은 UTF-8 인코딩 확인 (`file -I`)
