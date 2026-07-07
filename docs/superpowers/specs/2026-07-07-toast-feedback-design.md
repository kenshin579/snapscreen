# 편집기 인라인 토스트 피드백 설계 문서

- 날짜: 2026-07-07
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.8.1

## 1. 배경

OCR(v0.8.0) 사용 시 텍스트가 클립보드에 복사돼도 사용자가 실행 여부를 알 수 없다는 피드백. 원인: 성공 피드백이 `UNUserNotificationCenter` 시스템 배너(`Notifier.show`)에만 의존하는데, (1) 편집기 창을 보는 중 화면 우상단 배너를 놓치기 쉽고 (2) ad-hoc 서명 특성상 알림 권한이 리셋/미승인이면 배너가 아예 안 뜬다. 또한 이미지 복사(`⌘C`)는 현재 성공 피드백이 전혀 없다.

편집기 창은 작업 중 항상 앞에 있으므로, **창 내부에 인라인 토스트**로 피드백하면 알림 권한·서명과 무관하게 확실히 보인다.

## 2. 범위

- 편집기 캔버스 위에 뜨는 짧은 토스트 오버레이 신설
- 성공/안내 피드백을 토스트로 전환·추가:
  - OCR 복사 성공 → "N자를 복사했습니다"
  - OCR 텍스트 없음 → "인식된 텍스트가 없습니다"
  - 이미지 복사(`⌘C`) 성공 → "이미지를 복사했습니다" (신규 — 현재 무피드백)
- 하드 실패(OCR 실패/저장 실패)는 **기존 `Notifier.alertFailure`(beep + 시스템 알림) 유지** — 토스트는 성공/안내 전용

**비목표**: 토스트 큐잉/스택, 액션 버튼 포함 토스트, 위치·지속시간 사용자 설정, 저장 성공 토스트(저장은 창이 닫히므로 별도), 시스템 알림 완전 제거.

## 3. 구성 요소

| 파일 | 책임 | 상태 |
|---|---|---|
| `Editor/ToastView.swift` (신규) | 반투명 pill 형태 메시지 뷰(NSView). 배경+텍스트, 자체 페이드 애니메이션 | 신규 |
| `Editor/CanvasView.swift` (수정) | `showToast(_ message:)` — ToastView를 서브뷰로 캔버스 하단 중앙에 표시, 타이머로 자동 제거 | 수정 |
| `Editor/EditorWindowController.swift` (수정) | OCR/복사 성공·안내 시 `canvas.showToast(...)` 호출 | 수정 |

## 4. ToastView

- `NSView` 서브클래스. 둥근 모서리 반투명 어두운 배경(예: 검정 0.75 alpha) + 흰색 볼드 텍스트(`NSTextField` 또는 그리기). 좌우 패딩 있는 pill
- 크기는 텍스트에 맞춰 자동(intrinsic content size 또는 계산)
- `isReleasedWhenClosed`는 NSView라 무관. 재사용보다 표시 때마다 생성·제거로 단순화 가능

## 5. CanvasView.showToast

```swift
func showToast(_ message: String)
```

- 기존 토스트가 있으면 제거(새 메시지로 교체 — 큐잉 없음)
- `ToastView` 생성 → 캔버스 하단 중앙에 배치(하단에서 약간 위, 예: bottom+24pt, 가로 중앙). 오토레이아웃 또는 프레임 계산
- 표시 직후 alpha 0→1 페이드인(~0.15s), 약 1.5초 유지, alpha 1→0 페이드아웃(~0.3s) 후 `removeFromSuperview`
- 타이머/애니메이션은 `NSAnimationContext` 또는 `DispatchQueue.main.asyncAfter`. 창 닫힘 시 잔여 타이머가 접근해도 안전하도록 뷰 참조로만 동작(뷰가 제거되면 무해)
- 캔버스 리사이즈 시 위치는 다음 표시부터 반영(진행 중 토스트 재배치는 비목표 — 짧아서 무해)

## 6. 통합 (EditorWindowController)

- `copyMerged(_:)`: `ClipboardWriter.write` 성공 후 `canvas.showToast("이미지를 복사했습니다")`
- `performOCR()`:
  - 성공(비어있지 않음): 기존 `Notifier.show(...)` → `canvas.showToast("\(text.count)자를 복사했습니다")`
  - 텍스트 없음: `Notifier.show(...)` → `canvas.showToast("인식된 텍스트가 없습니다")`
  - 실패: `Notifier.alertFailure(...)` **유지**
- 저장 실패/폴백은 현행 유지(저장 성공은 창이 닫히므로 토스트 대상 아님)

## 7. 에러 처리 / 엣지

- 토스트 표시 중 창 닫힘: 뷰 계층과 함께 제거됨. asyncAfter 클로저는 뷰 참조만 만지므로(이미 슈퍼뷰에서 빠졌으면 no-op) 안전
- 연속 호출(빠른 반복): 이전 토스트 제거 후 새로 표시(교체)
- 매우 긴 메시지: 최대 폭 제한 + 말줄임(현 메시지들은 짧아 실사용 무관, 최대폭만 설정)

## 8. 테스트

- 토스트는 시각·타이머라 자동 단위 테스트 가치가 낮다. 표시 로직은 UI/타이밍 의존이라 수동 검증 위주
- **수동**: `docs/manual-test-checklist.md` "17. 복사 피드백 토스트" — OCR 복사/텍스트 없음/이미지 복사(⌘C) 시 캔버스 하단에 토스트가 뜨고 잠시 후 사라짐, 연속 실행 시 교체, 실패 시 기존 beep+알림 유지

## 9. 버전

v0.8.1 — `AppInfo.version` "0.8.1", `Info.plist` `CFBundleShortVersionString` "0.8.1", `CFBundleVersion` 11.
