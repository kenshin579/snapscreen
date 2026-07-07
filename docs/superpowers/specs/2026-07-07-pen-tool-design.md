# 펜(자유곡선) 도구 설계 문서

- 날짜: 2026-07-07
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.7.0

## 1. 배경

경쟁 앱 갭 분석 로드맵(crop → 펜 → OCR)의 두 번째 단계. 편집기에 손으로 그리는 자유곡선 주석을 추가한다. 마우스/트랙패드로 그린 획을 부드러운 곡선으로 렌더해 화살표·도형만으로는 어려운 강조(동그라미 표시, 밑줄, 손글씨)를 가능하게 한다.

## 2. 범위

- 단색 자유곡선 펜 **하나** — 색은 기존 6색 팔레트, 굵기는 기존 기본값(`3×scale`) 재사용
- 드래그로 그리기 → 실시간 미리보기 → 놓으면 확정(주석으로 추가)
- 그린 획은 다른 주석과 동일하게 **클릭 선택 / 드래그 이동 / undo·redo·⌫ 삭제**
- 곡선은 **렌더링 시에만** 이차 베지어 중점 스무딩으로 부드럽게. 저장 모델은 raw 점 배열
- 저장/복사(flatten)에 반영

**비목표**: 형광펜(반투명 하이라이터)·지우개(후속 기능), 굵기 프리셋 UI(기존 굵기 사용), 획 단순화(Douglas–Peucker 등), 필압/속도 기반 굵기 변화.

## 3. 데이터 모델 (`Editor/Annotation.swift`)

`AnnotationKind`에 케이스 추가:

```swift
case path([CGPoint])   // 이미지 픽셀 좌하단 좌표(기존 규약)의 획 점열
```

- `translated(by d:)`: `path(pts.map { CGPoint(x: $0.x + d.dx, y: $0.y + d.dy) })`
- `bounds`: 점들의 bounding box. 빈 배열이면 `.zero`(방어). 선택 테두리·다시그리기 영역 계산에 사용

`Annotation` 구조체(color/lineWidth 공용)는 변경 없음.

## 4. 도구 등록 (`Editor/EditorState.swift`, `Editor/ToolbarView.swift`)

- `EditorTool`에 `case pen` 추가
- `displayName`: "펜", `systemImage`: `scribble`
- 기존 도구 세그먼트 Picker(`EditorTool.allCases`)에 자동 편입 — 별도 UI 배선 불필요
- 색 팔레트/굵기는 기존 공용 상태(`EditorState.color`, `CanvasView.defaultLineWidth`) 재사용

## 5. 입력 (`Editor/CanvasView.swift`)

기존 `DragMode.drawing(start:)` 흐름을 펜에 맞게 확장한다. 펜은 시작점 하나가 아니라 점열을 누적해야 하므로, 드로잉 중 누적 점 배열을 `draft`의 `path`로 유지한다:

- `mouseDown`(도구 `.pen`, 이미지 영역 내): 누적 배열 시작 `[p]`, `draft = Annotation(kind: .path([p]), color:, lineWidth: defaultLineWidth)`
- `mouseDragged`: 점 추가 → `draft.kind = .path(points)` → `needsDisplay`
- `mouseUp`: 점이 **2개 이상**이면 `store.add(draft)`, 미만이면 무시(클릭만 한 경우 빈 획 방지). `draft = nil`

좌표는 기존 `imagePoint(from:)`로 이미지 픽셀 변환. 이미지 밖으로 나간 점은 기존 도형과 동일하게 별도 클램프하지 않되(자유곡선 특성), 그리기 시작(`mouseDown`)은 이미지 영역 내에서만 허용(기존 레터박스 클릭 무시 규칙 유지).

## 6. 렌더링 (`Editor/AnnotationRenderer.swift`, `Editor/PathSmoother.swift` 신규)

`AnnotationRenderer`는 캔버스 실시간 표시와 flatten 내보내기 공용이다. `path` 케이스 추가:

- 색상(`color`) + 굵기(`lineWidth`)로 stroke, `lineCap = .round`, `lineJoin = .round`
- 곡선 경로는 신규 순수 함수로 생성:

```swift
enum PathSmoother {
    /// 점열을 이차 베지어 중점 스무딩한 CGPath. 점 0개→빈 path, 1개→점(작은 dot), 2개→직선.
    static func smoothedPath(_ points: [CGPoint]) -> CGPath
}
```

중점 스무딩 알고리즘: `M p0`에서 시작, `i=1..n-2`에 대해 `addQuadCurve(to: midpoint(p[i], p[i+1]), control: p[i])`, 마지막에 `addLine(to: p[n-1])`. `CGMutablePath`로 구성 후 반환.

`PathSmoother`는 CoreGraphics만 의존(AppKit 비의존) → 단위 테스트 가능.

## 7. 선택·이동·삭제 (`Editor/AnnotationHitTester.swift`)

`path` 케이스: 인접 점들이 이루는 각 선분에 대해 점-선분 최단거리를 구해, 하나라도 `tolerance`(호출부에서 `8×scale`) 이내면 히트. 화살표의 선분 히트 로직과 동일한 점-선분 거리 헬퍼를 재사용/확장한다.

이동은 `AnnotationKind.translated`, 삭제/undo/redo/선택 상태는 `AnnotationStore`·`CanvasView`가 종류 무관하게 이미 처리하므로 추가 작업 없음. 선택 테두리는 `bounds` 기반(기존 공용 경로).

## 8. 에러 처리 / 엣지 케이스

- 점 2개 미만(클릭만): 주석 추가 안 함
- 빈 점 배열 `bounds`: `.zero` 반환(크래시 방지)
- 매우 긴 획(수천 점): 스무딩·stroke는 점 수에 선형이라 실용 범위에서 문제 없음. 별도 상한/단순화는 비목표

## 9. 테스트

- **단위** (`Tests/SnapScreenKitTests/`):
  - `PathSmoother`: 점 0개→빈 path(`isEmpty`), 2개→예상 시작/끝점, 중점 계산 정확성(`currentPoint` 또는 `boundingBox` 검증)
  - `AnnotationKind`: `.path` 의 `bounds`(bbox 정확), `translated`(모든 점 offset)
  - `AnnotationHitTester`: 곡선 선분 위 점은 히트, 멀리 떨어진 점은 미스
- **수동**: `docs/manual-test-checklist.md` "15. 펜" — 펜 선택/그리기, 곡선 부드러움, 색·굵기 반영, 획 클릭 선택 + 드래그 이동, ⌫/undo 삭제, ⌘S/⌘C에 반영, 이미지 경계 근처 그리기

## 10. 버전

v0.7.0 — `AppInfo.version` "0.7.0", `Info.plist` `CFBundleShortVersionString` "0.7.0", `CFBundleVersion` 9.
