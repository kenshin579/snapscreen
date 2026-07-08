# 지우개 도구 설계 문서

- 날짜: 2026-07-08
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.9.0

## 1. 배경

펜(자유곡선, v0.7.0) 도입 후 "그린 획의 일부만 다듬고 싶다"는 실사용 니즈. 기존에는 선택 + `⌫`로 주석을 통째 삭제만 가능하다. 지우개는 드래그로 문질러 **펜 획의 일부 구간을 지우고**(획 분할), **그 외 주석은 통째 삭제**하는 도구다. 펜 도구 후속으로 미뤄뒀던 기능.

## 2. 범위

- 편집기 도구에 지우개 추가(단축키 `X`), 드래그로 문질러 지움
- **펜 획(`path`)**: 지우개 브러시 반경 안의 점을 제거하고 남은 연속 구간을 조각으로 분할(각 조각이 새 획)
- **그 외 주석**(화살표·사각형·원·텍스트·블러·모자이크·배지): 브러시가 닿으면 **통째 삭제**
- 드래그 중 실시간 미리보기, 놓으면 결과를 **undo 1회**로 커밋
- 지우개 반경을 나타내는 **원형 커서** 표시(마우스 추적)
- 결과가 저장/복사(flatten)에 반영

**비목표**: 지우개 크기 조절 UI(고정 크기), 벡터 도형의 부분 지우기(불가 — 통째 삭제), 픽셀(이미지 자체) 지우기, 드래그 중 증분 최적화(전체 재계산으로 충분).

## 3. 구성 요소

| 파일 | 책임 | AppKit |
|---|---|---|
| `Editor/PathEraser.swift` (신규) | 점열 + 지우개 중심들 + 반경 → 남은 조각들(`[[CGPoint]]`) 순수 함수 | 비의존 (테스트 대상) |
| `Editor/EditorState.swift` (수정) | `EditorTool.eraser` 등록(label/symbol) | 비의존 |
| `Editor/AnnotationStore.swift` (수정) | `replace(with:)` 배치 트랜잭션(undo 1회) | 비의존 |
| `Editor/CanvasView.swift` (수정) | 지우개 입력(드래그+미리보기), 원형 커서(trackingArea/mouseMoved), 단축키 `x`, draw 분기 | 의존 |
| `Editor/ToolbarView.swift` | `EditorTool.allCases`로 자동 편입 (변경 없음) | 의존 |

## 4. 부분 지우기 순수 함수 (`PathEraser`)

```swift
public enum PathEraser {
    /// 점열에서 지우개 경로(centers)의 반경 안에 든 점을 제거하고,
    /// 남은 인덱스-연속 구간을 조각으로 분리해 반환. 2점 미만 조각은 버린다.
    /// 아무 점도 제거되지 않으면 [원본]을 그대로 반환, 전부 제거되면 [] 반환.
    public static func erase(_ points: [CGPoint],
                             along centers: [CGPoint],
                             radius: CGFloat) -> [[CGPoint]]
}
```

알고리즘: 각 점 `p`가 어떤 `center`에 대해 `hypot(p-center) <= radius`면 "지워짐". 지워지지 않은 점들을 원래 순서대로 훑어 인덱스가 끊기는 지점에서 조각을 분리. 각 조각이 2점 이상이면 결과에 포함.

## 5. 배치 트랜잭션 (`AnnotationStore.replace`)

```swift
public func replace(with newAnnotations: [Annotation]) {
    snapshot()
    annotations = newAnnotations
}
```

기존 `snapshot()`(undo 스택에 현재 배열 push + redo clear) 재사용. 지우개 드래그 결과 전체를 한 번에 커밋해 undo 1회로 복원된다.

## 6. 입력 + 미리보기 (`CanvasView`)

지우개는 여러 주석을 동시에 바꾸므로, 드래그 동안 store를 직접 건드리지 않고 **로컬 작업 배열**로 미리보기한다:

- `mouseDown`(도구 `.eraser`): `eraseCenters = [imagePoint]`, 이후 렌더/판정용 상태 활성화
- `mouseDragged`: `eraseCenters`에 현재 이미지 픽셀 좌표 추가 → 원본(`store.annotations`)에 누적 centers로 지우기 재적용한 결과를 로컬 `erasePreview`에 저장 → `needsDisplay`
- `mouseUp`: `erasePreview`가 원본과 다르면 `store.replace(with: erasePreview)`, 같으면 미커밋(빈 undo 방지). 상태 초기화
- `draw`: 지우개 진행 중이면 `store.annotations` 대신 `erasePreview`를 렌더

**지우기 적용 로직**(원본 배열 → 결과 배열):
```
각 주석 a:
  - a.kind == .path(pts):
      segments = PathEraser.erase(pts, along: centers, radius: r)
      각 segment(≥2점) → Annotation(id: 새 UUID, kind: .path(segment), color: a.color, lineWidth: a.lineWidth) 추가
      (segments 비면 완전 삭제)
  - 그 외:
      centers 중 하나라도 AnnotationHitTester.hitTest(center, [a], tolerance: r) != nil → 제거
      아니면 유지
```
분할 조각에 새 UUID를 부여하므로 이후 개별 선택/이동/undo와 충돌 없음.

## 7. 원형 커서 (`CanvasView`)

- `NSTrackingArea`(`.mouseMoved`, `.activeInKeyWindow`)를 `updateTrackingAreas`에서 갱신
- 지우개 도구일 때 `mouseMoved`로 현재 커서 위치(뷰/이미지 좌표) 저장 → `draw`에서 반경 원(테두리, 회색 반투명) 표시. 다른 도구면 표시 안 함
- 반경: 뷰 기준 지름 24pt → 이미지 픽셀 반경 `12 / fitScale`. 커서 원도 동일 반경으로 그려 판정과 시각이 일치

## 8. 좌표/스케일

- 모든 지우기 판정은 이미지 픽셀 좌표(기존 규약)
- 브러시 반경은 화면상 일정하게 보이도록 뷰 24pt를 `fitScale`로 이미지 픽셀 환산(`radiusInImage = 12 / fitScale`). 확대/축소된 창에서도 커서 원 크기와 판정 반경이 일치

## 9. 에러 처리 / 엣지

- 드래그가 아무 주석도 안 건드림: `mouseUp`에서 변경 없음 → 커밋 안 함
- 펜 획을 반경으로 관통: 여러 조각으로 분할, 2점 미만 조각은 소멸
- 지우개 도중 도구 전환: 기존 `state.$tool` sink가 crop을 취소하듯, 지우개 진행 상태도 도구 전환 시 정리(진행 중 배열 폐기, store 미변경)
- 빈 이미지/주석 없음: 지우기 결과가 원본과 동일 → 미커밋

## 10. 테스트

- **단위**:
  - `PathEraser.erase`: (a) 중간 점 제거 → 2조각, (b) 끝점만 제거 → 1조각, (c) 전 구간 제거 → 빈 배열, (d) 반경 밖 → [원본] 그대로, (e) 2점 미만 조각 버림
  - `AnnotationStore.replace`: 호출 후 `annotations` 교체 + `undo()`로 이전 배열 복원(1회), `redo()` 재적용
- **수동**: `docs/manual-test-checklist.md` "18. 지우개" — 펜 획 부분 지우기(분할 확인), 도형/텍스트 통째 삭제, 원형 커서 표시·반경 일치, 드래그 후 undo 1회 복원, 지운 결과 ⌘S/⌘C 반영, 확대/축소 창에서 반경 일관

## 11. 버전

v0.9.0 — `AppInfo.version` "0.9.0", `Info.plist` `CFBundleShortVersionString` "0.9.0", `CFBundleVersion` 13.
