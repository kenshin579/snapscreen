# Crop(자르기) 도구 설계 문서

- 날짜: 2026-07-06
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.5.0

## 1. 배경

경쟁 앱 갭 분석에서 crop은 편집기 도구 중 최대 갭(7/9 보유)이자 난이도 최하로, "캡처 후 다시 찍기"를 없애는 실사용 1순위 도구다. 합의된 로드맵(crop → 펜 → OCR)의 첫 단계.

MVP 브레인스토밍 때 확정한 핵심 결정을 따른다: **주석이 하나도 없을 때만 활성**(주석 좌표 변환/이미지 포함 undo의 복잡도 회피), 드래그 → 미리보기 → 확정/취소, crop 자체는 undo 불가(확정 전 미리보기라 취소 가능).

## 2. 범위

- 편집기 툴바에 crop 도구 추가 (단축키 `C`)
- 주석이 있으면 도구 비활성 (툴팁 안내)
- 드래그로 crop 영역 지정 → 선택 영역 근처에 확정(✓)/취소(✗) 버튼 + Enter/esc 단축
- 확정 시 **같은 편집기 창에서 이미지 교체** + 창 크기 새 비율로 재조정, 이어서 주석 작업 가능
- crop된 이미지가 저장/복사(flatten)에 반영

**비목표**: crop 후 주석 좌표 보존(주석 있으면 애초에 비활성), 종횡비 고정 crop, crop undo, 회전/플립

## 3. UX (합의된 방향)

- `.crop` 도구 선택 → crop 모드. 주석이 하나라도 있으면 툴바에서 비활성(회색 + 툴팁 "주석을 모두 삭제한 후 자를 수 있습니다"), `store.annotations.isEmpty`로 판정
- 드래그로 영역 지정: 선택 영역 밝게 + 나머지 어둡게(dimming, SelectionOverlay와 유사)
- 드래그 완료 후 선택 영역 우하단 근처에 확정(✓)/취소(✗) 버튼 2개를 `CanvasView` 서브뷰(NSButton)로 표시, 드래그 갱신 시 위치 이동
- Enter = 확정, esc = 취소(파워유저 단축), 마우스로는 버튼 클릭
- 취소 시 영역만 초기화(crop 모드 유지)

## 4. 구성 요소

| 파일 | 책임 | AppKit |
|---|---|---|
| `Editor/ImageCropper.swift` (신규) | `crop(_ image:toBottomLeftRect:) -> CGImage?` 순수 함수 — 좌표 변환 + cropping + 경계 클램프 | 비의존 (단위 테스트 대상) |
| `Editor/EditorState.swift` (수정) | `EditorTool.crop` 케이스 추가 | - |
| `Editor/CanvasView.swift` (수정) | crop 모드 상태(`cropRect`), 드래그, dimming 렌더, ✓/✗ 서브뷰 버튼, Enter/esc, 확정 콜백 | 의존 |
| `Editor/EditorWindowController.swift` (수정) | 현재 이미지 단일 소스(`var image`), crop 확정 시 이미지 교체 + 창 리사이즈 + 캔버스 갱신 | 의존 |
| `Editor/ToolbarView.swift` (수정) | crop 도구 세그먼트, 주석 있으면 비활성 | 의존 |

**crop은 주석이 아니다:** `AnnotationKind`에 넣지 않고 CanvasView의 별도 crop 모드 상태로 관리. 주석과 공존하지 않으므로(비활성 조건) 벡터 모델과 분리.

## 5. crop 실행 (좌표 함정)

`ImageCropper.crop(_ image: CGImage, toBottomLeftRect rect: CGRect) -> CGImage?`:
- crop rect는 이미지 픽셀 **좌하단** 좌표(코드베이스 규약). 그러나 `CGImage.cropping(to:)`은 데이터가 **좌상단** 원점이라 y를 뒤집어야 한다: `topLeftY = imageHeight - rect.maxY`
- 경계 클램프: rect를 `CGRect(0,0,width,height)`와 intersection. 결과가 비면 nil 반환
- scale은 불변 (픽셀 잘라내기라 Retina 배율 유지)

## 6. 확정 흐름 (통합)

1. CanvasView가 crop rect(이미지 픽셀 좌표)를 클로저로 EditorWindowController에 전달
2. 컨트롤러가 `ImageCropper.crop`으로 새 CGImage 생성
3. 컨트롤러가 보유 이미지(`var image`)를 새 것으로 교체 → `CanvasView.replaceImage(_:)`로 캔버스 갱신(fitScale/fitOffset 자동 재계산) → 창 content 크기를 새 비율로 재조정(기존 init 사이징 로직 재사용: 화면 visibleFrame 80% 이내 fit + 툴바 높이)
4. crop 모드 종료, ✓/✗ 버튼 숨김

**이미지 소유 정리:** 현재 `EditorWindowController`가 `result.image`를, `CanvasView`가 주입 image를 각각 보유. crop 후 flatten(저장/복사)도 crop된 이미지를 써야 하므로, 컨트롤러가 `private var image: CGImage`(+ scale)를 단일 소스로 두고 flatten의 base와 CanvasView를 이 값으로 동기화한다. `CanvasView.image`는 `let` → 교체 가능하게 하고 `replaceImage(_:)` 추가.

## 7. 에러 처리 / 엣지 케이스

- crop 영역이 최소 크기(8px) 미만이면 확정 무시(✓ 버튼 비표시 또는 무동작)
- `ImageCropper.crop`이 nil(빈 rect 등) 반환 시 crop 취소 처리, 이미지 변경 없음
- crop 도구 선택 중 주석 추가 불가(비활성 조건이 보장)

## 8. 테스트

- **단위 (`ImageCropper`)**: 좌표 변환(좌하단 rect → 좌상단 cropping, 결과가 기대 영역인지 픽셀 샘플로 검증), 결과 크기, 경계 밖 rect 클램프, 빈 rect → nil. `FlattenRendererTests`처럼 CGImage 생성으로 검증
- **수동**: `docs/manual-test-checklist.md`에 "13. 자르기" 섹션 — 도구 선택/드래그/dimming, ✓·✗ 버튼, Enter·esc, 확정 후 이미지·창 크기 변경, 주석 있을 때 비활성 + 툴팁, crop 후 이어서 주석 → 저장이 잘린 이미지+주석인지, crop 후 저장(⌘S)/복사(⌘C) 반영

## 9. 버전

v0.5.0 — AppInfo.version / Info.plist CFBundleShortVersionString "0.5.0", CFBundleVersion 6
