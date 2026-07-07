# OCR(텍스트 추출) 설계 문서

- 날짜: 2026-07-07
- 상태: 승인됨 (브레인스토밍 완료)
- 대상 릴리스: v0.8.0

## 1. 배경

경쟁 앱 갭 분석 로드맵(crop → 펜 → OCR)의 마지막 단계. 캡처한 스크린샷에서 텍스트를 추출해 클립보드로 복사하는 기능을 추가한다. "화면의 글자를 다시 타이핑하지 않고 바로 붙여넣기"라는 실사용 니즈를 충족한다. macOS Vision 프레임워크로 **온디바이스** 인식하므로 네트워크·프라이버시 문제가 없다.

## 2. 범위

- 편집기 툴바에 **OCR 버튼**(도구 세그먼트와 분리된 즉시 실행 액션) + 단축키 `E`
- 현재 편집기 이미지(`self.image`, crop 반영본) **전체**를 OCR → 인식 텍스트를 **클립보드(텍스트)** 로 복사
- 결과는 `Notifier` 알림으로 피드백(복사 글자 수). 인식 텍스트 없음/실패도 알림
- 언어 한국어+영어 자동, 인식 수준 `.accurate`

**비목표**: 영역 선택 OCR·별도 텍스트 캡처 모드(후속), 결과 미리보기/편집 시트, 언어 수동 설정 UI, OCR 결과를 텍스트 주석으로 이미지에 삽입, PDF/다중 페이지.

## 3. 구성 요소

| 파일 | 책임 | AppKit |
|---|---|---|
| `Editor/TextRecognizer.swift` (신규) | Vision `VNRecognizeTextRequest` 래퍼. `CGImage → String`(비동기). 관찰 정렬·결합 로직은 순수 함수로 분리 | Vision/CoreGraphics (결합 로직은 비의존) |
| `Output/ClipboardWriter.swift` (수정) | `write(text:)` 추가 — `NSPasteboard`에 문자열 쓰기 | 의존 |
| `Editor/ToolbarView.swift` (수정) | OCR 버튼(`text.viewfinder`) 추가, `onOCR` 클로저 | 의존 |
| `Editor/EditorWindowController.swift` (수정) | OCR 버튼/단축키 → 현재 이미지 OCR → 클립보드 복사 + 알림 | 의존 |
| `Editor/CanvasView.swift` (수정) | 단축키 `e`로 OCR 콜백 트리거(`onRequestOCR`) | 의존 |

## 4. OCR 엔진 (`TextRecognizer`)

```swift
enum TextRecognizer {
    /// 이미지에서 텍스트를 인식해 완료 핸들러로 결과 문자열을 돌려준다.
    /// 무거운 인식은 백그라운드에서 수행하고, 콜백은 메인 액터에서 호출한다.
    static func recognize(_ image: CGImage,
                          completion: @escaping @MainActor (Result<String, Error>) -> Void)

    /// (텍스트, 정규화 boundingBox minY) 목록을 위→아래로 정렬해 줄바꿈 결합. 순수 함수(테스트 대상).
    static func joinedText(_ lines: [(text: String, minY: CGFloat)]) -> String
}
```

- `VNRecognizeTextRequest`: `recognitionLevel = .accurate`, `recognitionLanguages = ["ko-KR", "en-US"]`, `usesLanguageCorrection = true`
- `VNImageRequestHandler(cgImage:).perform([request])`를 `DispatchQueue.global`에서 실행(UI 블로킹 방지) → 결과를 메인으로
- 결과 각 `VNRecognizedTextObservation.topCandidates(1).first?.string`과 `boundingBox.origin.y`를 모아 `joinedText`로 결합
- **정렬**: Vision의 boundingBox는 정규화 좌표(원점 좌하단)라 minY가 클수록 위쪽 → minY **내림차순**으로 정렬해 위에서 아래 순서로 줄바꿈 결합. 빈 결과면 빈 문자열

`joinedText`를 분리하는 이유: 실제 Vision 인식은 비결정적이라 단위 테스트가 어렵지만, 정렬·결합 규칙은 순수 함수로 검증 가능하다.

## 5. 클립보드 (`ClipboardWriter.write(text:)`)

```swift
static func write(text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}
```

기존 `write(_ image:scale:)`와 별개. 이미지 복사(⌘C)와 텍스트 복사(OCR)는 독립.

## 6. 통합 흐름

1. 편집기 툴바 OCR 버튼 클릭 또는 단축키 `E` → `EditorWindowController`가 현재 `self.image`로 `TextRecognizer.recognize` 호출
2. 완료(메인 액터):
   - 성공 & 비어있지 않음: `ClipboardWriter.write(text:)` + `Notifier.show("텍스트 복사됨", "\(count)자를 클립보드에 복사했습니다")`
   - 성공 & 빈 문자열: `Notifier.show("텍스트 없음", "이미지에서 인식된 텍스트가 없습니다")`
   - 실패: `Notifier.alertFailure("OCR 실패", 에러 설명)`
3. crop으로 이미지가 교체된 경우에도 `self.image`가 최신이라 crop된 영역 기준으로 인식

툴바 배선은 crop 버튼(`onCrop`)과 동일한 클로저 주입 패턴. 단축키 `e`는 `CanvasView.keyDown`에서 처리하되, OCR은 컨트롤러 책임이라 `onRequestOCR: (() -> Void)?` 콜백으로 위임(캔버스는 이미지 소유 아님). crop의 `beginCrop` 트리거와 유사.

## 7. 에러 처리 / 엣지 케이스

- 인식 텍스트 없음: 하드 실패 아님 → `Notifier.show` 안내
- Vision `perform` throw / 결과 nil: `Notifier.alertFailure`
- OCR 진행 중 편집기 창이 닫힘: 콜백에서 `[weak self]`로 self nil 시 무시
- 텍스트 편집 중(텍스트 필드 열림) OCR 트리거: `commitTextFieldIfNeeded()` 후 진행(기존 패턴). 단축키 `e`가 텍스트 입력과 충돌하지 않도록, 텍스트 필드가 first responder일 때는 `e`가 그 필드로 가고 OCR은 트리거되지 않음(기존 keyDown 구조가 보장 — 텍스트 편집 중엔 캔버스가 first responder 아님)

## 8. 테스트

- **단위**:
  - `TextRecognizer.joinedText`: 여러 줄이 minY 내림차순(위→아래)으로 결합되는지, 빈 배열 → 빈 문자열, 한 줄 → 그대로
  - `ClipboardWriter.write(text:)`: 쓴 뒤 `NSPasteboard.general.string(forType:.string)`로 되읽어 일치 확인
- **수동**: `docs/manual-test-checklist.md` "16. OCR" — 한글 이미지/영문 이미지에서 텍스트 추출·복사·붙여넣기, 텍스트 없는 이미지 안내, crop 후 OCR 결과가 잘린 영역 기준인지, 단축키 `E`

## 9. 버전

v0.8.0 — `AppInfo.version` "0.8.0", `Info.plist` `CFBundleShortVersionString` "0.8.0", `CFBundleVersion` 10.
