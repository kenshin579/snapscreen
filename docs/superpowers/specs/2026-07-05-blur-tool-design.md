# 블러 도구 설계 문서

- 날짜: 2026-07-05
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.3.0

## 1. 배경

경쟁 앱 갭 분석(9개 앱 대조) 결과, 가우시안 블러는 **9/9 전부**가 모자이크와 별개 도구로 보유한 유일한 항목이었다. 또한 현재 SnapScreen의 픽셀레이트 도구가 UI에 "블러"로 표시되고 있어 명칭 혼란이 있다.

v0.3.0부터는 기능 하나당 사이클(설계→계획→구현→PR→릴리스) 방식으로 진행한다. 이 문서는 그 첫 번째다. 이후 예정: crop → 펜(자유곡선) → OCR.

## 2. 범위

1. **모자이크 라벨 정리** — `EditorTool.pixelate`의 label을 "블러"에서 "모자이크"로 수정 (동작 변경 없음)
2. **블러 도구 신규** — `EditorTool.blur`, 단축키 `G`, 드래그로 영역 지정 → 가우시안 블러 적용. UX는 모자이크와 동일

**비목표**: 블러 강도 조절 UI, 브러시형(문지르기) 블러, 기존 주석의 블러↔모자이크 전환

## 3. 사용 구분 (문서화 필수)

| 도구 | 용도 | 알고리즘 |
|---|---|---|
| 모자이크 (`B`) | 민감정보 가리기 — 복원 불가 강도 보장 | CIPixellate, blockSize ≥ 12×scale |
| 블러 (`G`) | 시각적 완화 — 배경 정리, 시선 유도 | CIGaussianBlur |

약한 가우시안 블러는 복원 공격이 가능하므로 민감정보에는 모자이크를 권장한다. 이 구분을 README와 도구 툴팁(help)에 명시한다.

## 4. 구현 설계

기존 주석 아키텍처에 그대로 얹힌다:

- `AnnotationKind`에 `.blur(CGRect)` 케이스 추가 — `translated(by:)`/`bounds`는 `.pixelate`와 동일 패턴
- `AnnotationHitTester` — pixelate와 동일하게 bounds 포함 판정 (기존 `.text, .pixelate` 분기에 합류)
- `AnnotationRenderer` — CIGaussianBlur 렌더링. 기존 pixelate 파이프라인(경계 clamp → CIFilter → crop → UUID 키 캐시) 재사용:
  - **가장자리 번짐 처리**: CIGaussianBlur는 경계 밖이 투명으로 새므로 `CIImage.clampedToExtent()` 적용 후 결과를 clamped rect로 crop하는 표준 처리
  - 반경: `max(8 * scale, min(width, height) / 24)` — Retina scale 보정 (모자이크 blockSize와 같은 논리)
  - 캐시: 기존 `pixelateCache` 공유 (키가 annotation UUID라 충돌 없음)
- `EditorTool`에 `.blur` 케이스 — label "블러", symbolName "drop.halffull", CanvasView keyDown 매핑 `g`, makeDraft 분기 (pixelate와 동일하게 rect 드래그)
- 툴바는 `EditorTool.allCases` 순회라 자동 반영. 케이스 순서: pixelate 다음에 blur (모자이크·블러 인접 배치)

## 5. 에러 처리

기존 pixelate와 동일 — CIFilter 실패 시 해당 주석만 그리지 않음 (nil 반환 경로 기존과 동일).

## 6. 테스트

- FlattenRenderer 테스트: blur 주석 포함 시 dimensions 보존 1개 추가
- 스모크 (임시): 그라데이션 이미지에 blur 적용 → 원본과 픽셀이 다른지 + 결과가 모자이크와 다른지(블록 패턴 부재) 확인 후 삭제
- 수동: `docs/manual-test-checklist.md` §5에 항목 추가 — "블러 도구(G)로 가린 영역이 부드럽게 흐려진다 (모자이크와 구분됨)", "모자이크 도구 라벨이 '모자이크'로 표시된다"

## 7. 버전

v0.3.0 — AppInfo.version / Info.plist CFBundleShortVersionString "0.3.0", CFBundleVersion 3
