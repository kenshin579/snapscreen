# SnapScreen 편집기 리디자인 (Editor Redesign)

작성일: 2026-07-11
상태: 확정 (구현 대기)

## 배경

macOS Tahoe 네이티브 스타일 리디자인 전체 중 **세 번째 하위 프로젝트**이자 가장 규모·리스크가 큰 단계. 공통 기반(PR #28)·홈(PR #29)은 병합 완료.

전체 분해: 공통 기반(완료) → 홈(완료) → **편집기(이 문서)** → 설정.

디자인 원안: 핸드오프 README `§2. 편집기 (2b / 2e)`.

## 목표

편집기의 상단 가로 툴바를 `[좌측 도구 레일(52pt) | 캔버스 | 우측 인스펙터(170pt)]` 가로 레이아웃 + 타이틀바 버튼 구조로 재구성한다. 신규 상태 `lineWidth`·`shadowEnabled`를 도입하고, 핸드오프 주석 팔레트(동적 라이트/다크)를 적용하며, 캔버스에 중립 그라디언트 배경 + 이미지 드롭섀도를 준다.

**기존 동작은 전부 유지**: 캡처/주석 그리기(9종)/crop/OCR/undo·redo/복사·저장/펜/지우개/히스토리, 그리고 메인 메뉴 단축키(⌘Z/⇧⌘Z/⌘C/⌘S 등). **내보내기 결과물(FlattenRenderer)은 배경/캔버스 그림자를 포함하지 않아 불변** — 단, 주석 그림자는 주석의 일부이므로 내보내기에 포함된다.

## 비목표

- 설정 리디자인 (별도 하위 프로젝트).
- 주석 편집 UX 확장(기존 주석 소급 색/굵기 변경 등) — `lineWidth`/`shadowEnabled`/`color`는 기존 `color`와 동일하게 **새로 그리는 주석에만** 적용.
- 캔버스 좌표계·스케일 스레딩·crop 로직 변경 — 배경/그림자 표시만 손댄다.

## 핵심 설계 결정 (브레인스토밍 확정)

1. **`shadowEnabled` 저장**: `Annotation`에 per-annotation 필드로 저장(=`lineWidth`와 대칭). 생성 시 `EditorState.shadowEnabled`를 구움. 렌더러 시그니처 불변, 내보내기 일관성 자동.
2. **타이틀바 버튼**: `NSTitlebarAccessoryViewController`(trailing)에 SwiftUI 버튼 호스팅. 네이티브 타이틀바·트래픽 라이트·중앙 타이틀 유지.
3. **타이틀 파일명**: 편집기 열릴 때 `FilenameFormatter(prefix: settings.filenamePrefix).filename(for: 열린 시각)`으로 생성한 예정 파일명.
4. **팔레트**: `PaletteColor`를 `red/orange/yellow/green/blue/label`로 재작업, 동적 라이트/다크 nsColor(핸드오프 hex). `drawBadge` 대비 로직을 명도 기반으로 일반화.
5. **빠른 작업 중복**: 핸드오프대로 레일 하단(아이콘)과 인스펙터(라벨 리스트) 양쪽에 crop·OCR 배치.

## 변경 대상 파일

- **Modify** `Sources/SnapScreenKit/Editor/EditorState.swift` — `lineWidth`, `shadowEnabled` 추가.
- **Modify** `Sources/SnapScreenKit/Editor/Annotation.swift` — `Annotation.shadowEnabled` 추가; `PaletteColor` 케이스 재작업.
- **Modify** `Sources/SnapScreenKit/Editor/AnnotationRenderer.swift` — `PaletteColor.nsColor` 동적 라이트/다크; 그림자 적용; `drawBadge` 대비 로직.
- **Modify** `Sources/SnapScreenKit/Editor/CanvasView.swift` — `defaultLineWidth`를 `state.lineWidth`에서; 주석 생성에 `shadowEnabled`; 배경 그라디언트 + 이미지 드롭섀도.
- **Modify** `Sources/SnapScreenKit/Editor/EditorWindowController.swift` — 레이아웃(레일|캔버스|인스펙터), 타이틀바 접근성 뷰, 파일명 타이틀.
- **Delete/Replace** `Sources/SnapScreenKit/Editor/ToolbarView.swift` → 신규 `ToolRailView.swift` + `InspectorView.swift` + `EditorTitlebarButtons.swift`로 분리.
- **Modify** `Sources/SnapScreenKit/Editor/AnnotationStore.swift` — 필요 시 `canUndo`/`canRedo` 노출(타이틀바 redo 비활성용).
- **Modify** 관련 테스트 — `PaletteColor`/`Annotation` init 변경에 맞춰 업데이트.

## 설계

### 1. 상태 & 모델

**EditorState** (+2):
```swift
@Published public var lineWidth: CGFloat = 3      // points (pre-scale)
@Published public var shadowEnabled: Bool = true
```

**Annotation** (+1, `lineWidth`와 대칭):
```swift
public var shadowEnabled: Bool   // init 파라미터 추가, 기본 false
```
생성 시 `CanvasView`가 `state.shadowEnabled`를 구워 넣는다.

**PaletteColor**:
- 케이스: `red, orange, yellow, green, blue, label`
- `nsColor`: 동적 라이트/다크. 라이트 `#FF3B30 #FF9500 #FFCC00 #34C759 #007AFF #1D1D1F`, 다크 `#FF453A #FF9F0A #FFD60A #30D158 #0A84FF #F5F5F7`. (AppKit `NSColor(name:dynamicProvider:)` — 공통 기반의 동적 색 패턴과 동일하되 여기선 `NSColor` 반환.)
- `EditorState.color` 기본 `.red` 유지.

**AnnotationRenderer**:
- `draw(_ annotation:)`에서 `annotation.shadowEnabled == true`면 도형 그리기 전 `ctx.saveGState()` → `ctx.setShadow(offset:blur:color:)` → 그림 → `ctx.restoreGState()`. 적용 대상: arrow/rectangle/ellipse/text/stepBadge/path. **pixelate/blur 제외**(이미지 영역이라 그림자 무의미·보안 목적 훼손 방지).
- `drawBadge` 대비: 기존 `color == .white ? .black : .white`를 명도 기반으로 일반화 — 밝은 색(yellow, 라이트 모드 label 등)이면 어두운 글자, 어두운 색이면 흰 글자. 색의 상대 명도(luminance)로 판정.

**CanvasView**:
- `defaultLineWidth`: `3 * captureScale` → `state.lineWidth * captureScale`.
- 주석 생성 지점(현 라인 237/243/351/573)에 `shadowEnabled: state.shadowEnabled` 추가.

### 2. 창 레이아웃 (`EditorWindowController`)

- 타이틀바:
  - `window.title = FilenameFormatter(prefix: settings.filenamePrefix).filename(for: Date())` (열릴 때 1회) → 중앙 자동 표시.
  - `NSTitlebarAccessoryViewController(layoutAttribute: .trailing)` + `NSHostingView(EditorTitlebarButtons)`(undo/redo/복사/저장). redo는 `store.canRedo == false`면 opacity 0.35.
  - 트래픽 라이트 시스템 유지.
- 본문 컨테이너(AutoLayout):
  - 좌: `NSHostingView(ToolRailView)` 폭 52, 우측 hairline.
  - 중: 기존 `CanvasView`(불변, 배경/그림자만 내부에서).
  - 우: `NSHostingView(InspectorView)` 폭 170, 좌측 hairline.
  - `minSize` = 52 + 170 + 최소 캔버스 폭 + 여유.
- 유지: `toolCancellable`(도구 전환 시 crop/erase 취소), crop 확정 리사이즈, 메인 메뉴 nil-target 셀렉터(`saveImage:`/`undoAction:`/`redoAction:`/`copyMerged:`).

### 3. 좌측 도구 레일 (`ToolRailView` 신규)

- 폭 52, 반투명 재질, 우측 hairline.
- 9개 도구 버튼(`EditorTool.allCases` 순서·심볼 유지) 36×32, radius 9(`Radius.tool`), 세로 gap 4. `state.tool` 라디오. 선택 = 액센트 배경 + 흰 아이콘. 툴팁 = `EditorTool.label`.
- `Spacer()` 후 하단: 자르기(`crop` → `onCrop`, `store.annotations` 비어있지 않으면 disabled + 기존 툴팁), 텍스트 추출(`text.viewfinder` → `onOCR`).

### 4. 우측 인스펙터 (`InspectorView` 신규)

폭 170, 패딩 14, 섹션 gap 16, 섹션 라벨 11pt semibold secondary.
- **색상**: 6 스와치 18pt 원형, 6열 그리드 gap 6. 선택 = 2px 배경색 링 + 3.5px 액센트 링(overlay 이중 원). `state.color`.
- **선 굵기**: `Slider(value: $state.lineWidth, in: 1...12, step: 1)` + "`\(Int(state.lineWidth))`px" 11pt `.monospacedDigit()`.
- **그림자**: 라벨 12pt + `Toggle(isOn: $state.shadowEnabled)`.
- 구분선 후 **빠른 작업**: "텍스트 추출"(→`onOCR`)·"자르기"(→`onCrop`) 리스트 버튼 12pt, radius 8, 토큰 배경. (레일과 동일 동작 — 의도된 중복.)

### 5. 캔버스 배경 & 이미지 그림자 (`CanvasView.draw`)

- 배경: `windowBackgroundColor` 단색 → 중립 radial 그라디언트. 라이트 `#E3E6EC→#D3D7DF` / 다크 `#2C3240→#1F2229`. `effectiveAppearance` 기준 분기(AppKit).
- 이미지: 기존 중앙 배치/`fitScale` 유지 + 드롭섀도.
- **표시 전용**: `FlattenRenderer`(내보내기)에는 미적용. 기존 crop 오버레이·선택 하이라이트·펜 커서 렌더 유지.

### 6. 파일 분리

`ToolbarView.swift`(84줄)를 삭제하고 역할별로 분리: `ToolRailView.swift`(도구 레일), `InspectorView.swift`(인스펙터), `EditorTitlebarButtons.swift`(타이틀바 버튼). 각 파일 단일 책임.

## 테스트 / 검증

- `swift build` + `swift test`. **팔레트/Annotation init 변경으로 깨질 수 있는 테스트를 함께 수정**: `FlattenRendererTests`, `BlurRenderTests`, `AnnotationBoundsTests`, `PenAnnotationTests`, `AnnotationHitTesterTests`, `AnnotationStoreTests` 등에서 `Annotation(...)` 생성·`PaletteColor.white` 참조 여부 확인.
- **실제 앱 실행 육안 검증**(`Scripts/run.sh` → 캡처 → 편집기): 레일 도구 선택, 인스펙터 색/굵기/그림자, 타이틀바 버튼(undo/redo/복사/저장, redo 비활성), 캔버스 배경/이미지 그림자, 라이트/다크. **회귀**: 9종 주석 그리기·crop(주석 있을 때 비활성)·OCR·undo/redo·복사·저장·펜·지우개·번호 배지 대비.
- 내보내기 회귀: 저장/복사 결과물에 배경·캔버스 그림자 없음, 주석 그림자는 포함 확인.
- 한글 소스 UTF-8.

## 완료 기준

- 위 파일 수정/신설, `swift build`/`swift test` 통과(수정된 테스트 포함).
- 실제 앱 실행 육안 검증(레이아웃·색·그림자·회귀).
- 기존 기능·단축키 회귀 없음.

## 다음 단계

편집기 완료 후 마지막 하위 프로젝트 **설정 리디자인**(grouped Form → 사이드바 2-pane)으로 진행.
