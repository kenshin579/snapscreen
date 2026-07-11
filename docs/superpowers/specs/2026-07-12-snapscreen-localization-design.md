# SnapScreen 다국어 지원 (Localization: ko + en)

작성일: 2026-07-12
상태: 확정 (구현 대기)

## 배경 / 문제

모든 UI 문자열(약 135곳, 19개 파일)이 한국어 리터럴로 하드코딩되어 있어, 시스템 언어와 무관하게 모든 사용자에게 한국어가 표시된다. 리디자인 4부작(PR #28~#31) 완료 후 보류했던 과제.

참고: 도구 레일의 텍스트 아이콘("가가")은 SF Symbol `textformat`의 시스템 자동 로컬라이즈라 이 작업의 대상이 아니다(영어 시스템에서 "Aa"로 자동 표시).

## 목표

- 시스템 언어에 따라 **영어/한국어** UI 자동 전환. 그 외 언어는 영어로 폴백.
- **코드는 영어 우선**(브레인스토밍 확정): 기존 한국어 리터럴을 영어 리터럴 키로 재작성하고, `ko.lproj`가 한국어 번역을 공급.
- 키 누락을 CI에서 차단하는 회귀 테스트.

## 비목표

- 일본어 등 추가 언어 (이후 `.lproj` 파일 추가로 확장 가능).
- `.xcstrings`(String Catalog) 도입 — Xcode 중심 포맷이라 순수 `swift build` 호환이 불확실. 검증된 `.lproj/.strings` 사용(Swift 5.3+ SwiftPM 공식 지원, diff 리뷰 용이).
- 파일명 접두어 기본값 "snapscreen"(파일명 구성요소), 개발자용 로그 문자열.

## 설계

### 1. 인프라

- **Package.swift**: `defaultLocalization: "en"`, SnapScreenKit 타깃에 `resources: [.process("Resources")]`.
- **리소스 구조**:
  ```
  Sources/SnapScreenKit/Resources/
  ├── en.lproj/Localizable.strings   ← 영어 (키=값 항등)
  └── ko.lproj/Localizable.strings   ← 한국어 번역
  ```
- **헬퍼** (`Sources/SnapScreenKit/Support/Localization.swift`):
  ```swift
  /// SnapScreenKit 모듈 번들에서 로컬라이즈. 보간은 String.LocalizationValue가 포맷 키로 변환.
  func L(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }
  ```
  호출: `Text(L("Area"))`, 동적 문자열은 `L("Copied \(count) characters")` → `.strings` 키 `"Copied %lld characters"`.
- **번들 배포**: `Scripts/bundle.sh`의 기존 `.build/$CONFIG/*.bundle` 복사+심링크 루프가 신규 `SnapScreen_SnapScreenKit.bundle`을 자동 처리(KeyboardShortcuts 번들과 동일 메커니즘). 구현 시 번들 생성·복사 여부 확인.
- **Resources/Info.plist**: `CFBundleDevelopmentRegion` → `en`, `CFBundleLocalizations` = `en, ko` 추가(앱별 언어 선택 활성화).

### 2. 회귀 테스트 (`LocalizationTests`)

- `en.lproj`/`ko.lproj`의 `Localizable.strings`를 `NSDictionary(contentsOf:)`로 파싱해:
  1. 두 파일의 **키 집합 완전 일치**
  2. 모든 값 비어있지 않음
- 경로는 `#filePath` 기준(AppInfoTests의 Info.plist 테스트와 동일 패턴).

### 3. 적용 범위 (19개 파일, ~135곳)

홈(타일·최근 캡처·푸터·다이얼로그), 편집기(도구 라벨/툴팁 9종·인스펙터·타이틀바 버튼·토스트·OCR/저장 메시지), 설정(사이드바 4항목·페인·캡션·recorder 라벨), AppCore(MainMenuBuilder·StatusItemController 메뉴·AppDelegate 알림), Updater(상태 텍스트·설치 오류·알림), CaptureKit(권한 안내·캡처 오류), 접근성 문자열(accessibilityLabel/Hint, "지우개" 커서 설명).

동적 문자열 예: `"Copied %lld characters"`, `"Saved to Desktop: %@"`, `"v%@ available"`, `"Updated to SnapScreen %@"`.

`KeyboardShortcuts.Recorder`는 라이브러리 자체 로컬라이제이션(en/ko 포함)을 그대로 사용.

### 4. 검증

- `swift build` / `swift test` (신규 LocalizationTests 포함, 기존 89개 회귀 없음).
- **양 언어 실행 확인**: 한국어 시스템 그대로 실행(한국어 확인) + `-AppleLanguages "(en)"` 인자로 영어 UI 강제 실행(영어 확인) — 시스템 언어 변경 불필요.
- 배포 zip에 `SnapScreen_SnapScreenKit.bundle`이 포함되는지 확인(누락 시 `Bundle.module` 크래시 — bundle.sh의 기존 가드가 심링크 유효성 검사).
- 한글 포함 파일(ko.lproj) UTF-8 확인.

## 완료 기준

- 전 UI 문자열 영어 키 + ko 번역, 두 언어 실행 육안 확인, 테스트 통과.
- 기존 기능·레이아웃 회귀 없음 (문자열 길이 변화로 인한 레이아웃 확인 — 특히 영어가 긴 버튼/캡션).

## 다음 단계

완료 후 버전 범프(0.13.0 — 사용자 가시 기능) + 릴리스.
