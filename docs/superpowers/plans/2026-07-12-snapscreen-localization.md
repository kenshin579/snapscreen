# 다국어 지원 (ko + en) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 하드코딩된 한국어 UI 문자열(~135곳, 19파일)을 영어 키로 재작성하고 `ko.lproj`가 한국어를 공급하게 하여, 시스템 언어에 따라 영어/한국어가 자동 전환되게 한다(그 외 언어는 영어 폴백).

**Architecture:** Task 1이 인프라(Package.swift `defaultLocalization`, `L()` 헬퍼, en/ko `.strings` 스켈레톤, Info.plist, 키 일치 테스트)를 깐다. Task 2~4가 영역별로 기계적 변환(코드의 한국어 리터럴 → 영어 키 `L("...")` + 양쪽 `.strings`에 항목 추가)을 수행하되 **매 태스크 종료 시 `LocalizationTests`(키 집합 일치)가 green**이어야 한다. Task 5가 배포 번들·양 언어 실행을 검증한다.

**Tech Stack:** Swift, SwiftPM localized resources(`.lproj/.strings`), `String(localized:bundle:)`, XCTest.

**참고 스펙:** `docs/superpowers/specs/2026-07-12-snapscreen-localization-design.md`

---

## 변환 규약 (모든 태스크 공통 — 반드시 준수)

1. **키 = 사용자에게 보일 영어 문장 그대로** (sentence case, 자연스러운 영어). 시맨틱 키 금지.
2. 코드 변환: `"한국어"` → `L("English")`. SwiftUI `Text("한국어")` → `Text(L("English"))`. `.help("한국어")` → `.help(L("English"))`.
3. **동적 문자열**: 코드는 보간 유지 — `L("Copied \(count) characters")`. `.strings` 키는 포맷 지정자 — 정수 `%lld`, 문자열 `%@`:
   ```
   "Copied %lld characters" = "%lld자를 복사했습니다";
   ```
4. **양쪽 `.strings`에 동시 추가** — `en.lproj`는 키=값 항등(`"Copy" = "Copy";`), `ko.lproj`는 번역(`"Copy" = "복사";`). 한쪽만 추가하면 `LocalizationTests` 실패.
5. 단축키 힌트가 붙은 툴팁은 힌트 포함: `"Crop (C)"`, `"Undo (⌘Z)"` 등.
6. **비대상**: 파일명 접두어 기본값 `"snapscreen"`, 개발자 로그/주석, `KeyboardShortcuts.Recorder` 내부(라이브러리가 자체 로컬라이즈), SF Symbol 이름.
7. `.strings` 파일은 UTF-8, 각 항목 끝 세미콜론, 알파벳 순 정렬 유지(충돌·중복 방지).
8. 접근성 문자열(`accessibilityLabel`/`accessibilityHint`/`accessibilityDescription`)도 대상.

## 용어집 (일관성 — 태스크 간 동일 용어 강제)

| 한국어 | 영어 |
|---|---|
| 영역 / 창 / 전체 화면 | Area / Window / Full Screen |
| 캡처 | capture (동사 Capture) |
| 최근 캡처 | Recent Captures |
| 모두 지우기 | Clear All |
| 미설정 | Not Set |
| 색상 / 선 굵기 / 그림자 | Color / Line Width / Shadow |
| 빠른 작업 | Quick Actions |
| 텍스트 추출 / 자르기 | Extract Text / Crop |
| 복사 / 저장 | Copy / Save |
| 실행 취소 / 실행 복귀 | Undo / Redo |
| 단축키 / 저장(섹션) / 히스토리 / 정보 | Shortcuts / Saving / History / About |
| 보관 개수 | Keep Limit |
| 설정 | Settings |
| 화살표/사각형/원/텍스트/블러/모자이크/번호/펜/지우개 | Arrow/Rectangle/Ellipse/Text/Blur/Pixelate/Number/Pen/Eraser |
| 업데이트 확인 / 업그레이드 | Check for Updates / Upgrade |

---

## Task 1: 인프라 (Package.swift + 헬퍼 + 스켈레톤 + 테스트)

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SnapScreenKit/Support/Localization.swift`
- Create: `Sources/SnapScreenKit/Resources/en.lproj/Localizable.strings`
- Create: `Sources/SnapScreenKit/Resources/ko.lproj/Localizable.strings`
- Modify: `Resources/Info.plist`
- Test: `Tests/SnapScreenKitTests/LocalizationTests.swift`

- [ ] **Step 1: Package.swift 수정**

`.target(name: "SnapScreenKit", ...)` 줄과 `Package(name:...)` 을 다음처럼 변경:
```swift
let package = Package(
    name: "SnapScreen",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .target(name: "SnapScreenKit",
                dependencies: ["KeyboardShortcuts"],
                resources: [.process("Resources")]),
        .executableTarget(name: "SnapScreen", dependencies: ["SnapScreenKit"]),
        .testTarget(name: "SnapScreenKitTests", dependencies: ["SnapScreenKit"])
    ]
)
```

- [ ] **Step 2: 헬퍼 생성** — `Sources/SnapScreenKit/Support/Localization.swift`:
```swift
import Foundation

/// SnapScreenKit 모듈 번들에서 로컬라이즈한다.
/// 키는 사용자에게 보일 영어 문장 그대로이며, 보간은 String.LocalizationValue가
/// 포맷 키(%lld/%@)로 변환한다. 번역은 Resources/{en,ko}.lproj/Localizable.strings.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
```

- [ ] **Step 3: `.strings` 스켈레톤 생성** — 시드 키 1개로 시작(테스트/파이프라인 검증용).

`Sources/SnapScreenKit/Resources/en.lproj/Localizable.strings`:
```
"Copy" = "Copy";
```
`Sources/SnapScreenKit/Resources/ko.lproj/Localizable.strings`:
```
"Copy" = "복사";
```

- [ ] **Step 4: Info.plist** — `Resources/Info.plist`에서 `CFBundleDevelopmentRegion`을 확인해 없으면 추가하고 `en`으로, 그리고 `CFBundleLocalizations` 배열(`en`, `ko`) 추가:
```xml
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>ko</string>
	</array>
```

- [ ] **Step 5: 실패하는 테스트 작성** — `Tests/SnapScreenKitTests/LocalizationTests.swift`:
```swift
import XCTest
@testable import SnapScreenKit

final class LocalizationTests: XCTestCase {
    private func stringsDict(_ locale: String) throws -> [String: String] {
        // Tests/SnapScreenKitTests/LocalizationTests.swift → 패키지 루트
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SnapScreenKit/Resources/\(locale).lproj/Localizable.strings")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String],
                                 "\(locale).lproj/Localizable.strings 파싱 실패: \(url.path)")
        return dict
    }

    /// en/ko 키 집합이 완전히 일치해야 한다 — 한쪽만 추가하면 번역 누락.
    func testKeySetsMatch() throws {
        let en = try stringsDict("en"), ko = try stringsDict("ko")
        let onlyEN = Set(en.keys).subtracting(ko.keys)
        let onlyKO = Set(ko.keys).subtracting(en.keys)
        XCTAssertTrue(onlyEN.isEmpty, "ko.lproj에 누락된 키: \(onlyEN.sorted())")
        XCTAssertTrue(onlyKO.isEmpty, "en.lproj에 누락된 키: \(onlyKO.sorted())")
    }

    /// 모든 값이 비어있지 않아야 한다.
    func testNoEmptyValues() throws {
        for locale in ["en", "ko"] {
            for (key, value) in try stringsDict(locale) {
                XCTAssertFalse(value.isEmpty, "\(locale).lproj의 빈 값: \(key)")
            }
        }
    }

    /// L() 헬퍼가 모듈 번들에서 실제로 조회하는지 (시드 키).
    func testHelperResolvesFromModuleBundle() {
        XCTAssertFalse(L("Copy").isEmpty)
    }
}
```

- [ ] **Step 6: 빌드·테스트** — `swift build` 성공, `swift test` 통과(기존 89 + 신규 3 = 92). 리소스 처리로 `.build/debug/SnapScreen_SnapScreenKit.bundle`이 생성되는지 확인: `ls .build/debug/*.bundle`.

- [ ] **Step 7: bundle.sh 파이프라인 확인** — `Scripts/bundle.sh debug` 실행 후:
```bash
ls build/SnapScreen.app/Contents/Resources/ && ls build/SnapScreen.app/ | grep bundle
```
`SnapScreen_SnapScreenKit.bundle`이 Resources에 복사되고 루트 심링크가 생겼는지 확인(기존 KeyboardShortcuts 번들과 동일 처리). 안 되면 원인 보고.

- [ ] **Step 8: Commit**
```bash
git add Package.swift Sources/SnapScreenKit/Support/Localization.swift Sources/SnapScreenKit/Resources Resources/Info.plist Tests/SnapScreenKitTests/LocalizationTests.swift
git commit -m "feat: 로컬라이제이션 인프라 (defaultLocalization en·L 헬퍼·strings 스켈레톤·키 일치 테스트)"
```

---

## Task 2: 편집기 문자열 변환

**Files (Modify):** `Sources/SnapScreenKit/Editor/EditorState.swift`(도구 라벨 9종), `ToolRailView.swift`(자르기/텍스트 추출 툴팁), `InspectorView.swift`(색상/선 굵기/그림자/빠른 작업/버튼), `EditorTitlebarButtons.swift`(복사/저장/툴팁), `CanvasView.swift`(토스트·지우개 접근성·crop 버튼), `EditorWindowController.swift`(토스트·저장/OCR 메시지·알림), + 양쪽 `Localizable.strings`

- [ ] **Step 1:** 각 파일의 한국어 리터럴을 규약대로 `L("English")`로 변환하고 양쪽 `.strings`에 항목 추가. 대표 예:
  - `EditorState.label`: `"화살표"` → `L("Arrow")` … `"블러 (시각적 완화용 — 민감정보는 모자이크 사용)"` → `L("Blur (visual softening — use Pixelate for sensitive info)")`
  - 토스트: `"이미지를 복사했습니다"` → `L("Image copied")`, `"\(text.count)자를 복사했습니다"` → `L("Copied \(text.count) characters")` / `.strings`: `"Copied %lld characters"`
  - `"저장 실패"` → `L("Save Failed")`, `"저장 위치 폴백"` → `L("Save Location Fallback")`, `"데스크탑에 저장했습니다: \(url.lastPathComponent)"` → `L("Saved to Desktop: \(url.lastPathComponent)")` / `"Saved to Desktop: %@"`
- [ ] **Step 2:** `swift build` && `swift test`(LocalizationTests 포함 전부 green) && 변환 누락 확인: `grep -rn '"[^"]*[가-힣][^"]*"' Sources/SnapScreenKit/Editor/ --include="*.swift"` 결과가 주석/비대상뿐인지 확인.
- [ ] **Step 3:** Commit — `feat: 편집기 UI 문자열 로컬라이즈 (영어 키 + ko 번역)`

---

## Task 3: 홈 + 설정 문자열 변환

**Files (Modify):** `Home/HomeView.swift`(타일 3종·미설정·최근 캡처·모두 지우기·다이얼로그·빈 상태·삭제·설정 열기·접근성), `Home/HomeWindowController.swift`(창 타이틀 확인 — "SnapScreen"은 고유명사라 비대상), `Settings/SettingsView.swift`(섹션 4종 라벨), `Settings/SettingsPanes.swift`(페인 타이틀·recorder 라벨·저장 폴더·접두어·보관 개수·버전·업데이트 상태/버튼·캡션·NSAlert), `Settings/SettingsWindowController.swift`(창 타이틀 "SnapScreen 설정" → `L("SnapScreen Settings")`), + 양쪽 `.strings`

- [ ] **Step 1:** 규약대로 변환. 대표 예:
  - `"영역"` → `L("Area")`, `"미설정"` → `L("Not Set")`, `"최근 캡처를 모두 지울까요?"` → `L("Clear all recent captures?")`
  - `"시스템 스크린샷 위치 따름"` → `L("Follows system screenshot location")`
  - `"\($0)개"` (Picker) → `L("\(count) items")` / `"%lld items"` = `"%lld개"` (클로저 인자를 지역 변수로 받아 보간)
  - `"v\(version) 사용 가능"` → `L("v\(version) available")` / `"v%@ available"`
  - `"최신 버전입니다 ✓"` → `L("Up to date ✓")`
- [ ] **Step 2:** build/test green + 잔여 한글 grep 확인 (Home/, Settings/).
- [ ] **Step 3:** Commit — `feat: 홈·설정 UI 문자열 로컬라이즈`

---

## Task 4: AppCore + Updater + CaptureKit 문자열 변환

**Files (Modify):** `AppCore/MainMenuBuilder.swift`(메뉴 항목), `AppCore/StatusItemController.swift`(메뉴바 메뉴), `AppCore/AppDelegate.swift`(알림·열 수 없음), `AppCore/CaptureCoordinator.swift`(캡처 실패 알림), `Updater/UpdateChecker.swift`, `Updater/UpdateInstaller.swift`(설치 오류·완료 안내), `CaptureKit/ScreenCapturePermission.swift`(권한 안내), `CaptureKit/CaptureEngine.swift`(오류), `DesignSystem/ShortcutKeycaps.swift`(해당 리터럴이 UI 노출이면 변환, 주석이면 비대상 — 확인), + 양쪽 `.strings`

- [ ] **Step 1:** 규약대로 변환. 대표 예:
  - 메뉴: `"설정…"` → `L("Settings…")`, `"종료"` → `L("Quit")` 등 (기존 메뉴 항목 전수)
  - `"SnapScreen \(AppInfo.version)(으)로 업데이트됨"` → `L("Updated to SnapScreen \(AppInfo.version)")` / `"Updated to SnapScreen %@"` = `"SnapScreen %@(으)로 업데이트됨"`
  - `"화면 기록 권한을 다시 켜야 할 수 있습니다."` → `L("You may need to re-enable Screen Recording permission.")`
  - `relaunchFailedMessage`, `"다운로드한 앱 검증에 실패했습니다"`, `"업데이트 실패: ..."` 등 전부
- [ ] **Step 2:** build/test green + **전체 잔여 한글 최종 확인**: `grep -rn '"[^"]*[가-힣][^"]*"' Sources/ --include="*.swift"` — 남은 것이 주석/비대상(파일명 접두어 등)뿐이어야 함. 목록을 보고서에 첨부.
- [ ] **Step 3:** Commit — `feat: 메뉴·알림·업데이터·캡처 문자열 로컬라이즈`

---

## Task 5: 배포·양 언어 검증

- [ ] **Step 1:** `Scripts/bundle.sh debug` → `build/SnapScreen.app`에 `SnapScreen_SnapScreenKit.bundle`(en/ko lproj 포함) 확인:
```bash
ls "build/SnapScreen.app/Contents/Resources/SnapScreen_SnapScreenKit.bundle/Contents/Resources/" | grep lproj
```
- [ ] **Step 2:** 한국어 확인 — `Scripts/run.sh` 실행(한국어 시스템) → 홈 창이 한국어인지. 종료.
- [ ] **Step 3:** 영어 확인 — 앱을 영어로 강제 실행:
```bash
pkill -f "build/SnapScreen.app"; open build/SnapScreen.app --args -AppleLanguages "(en)"
```
(안 먹으면 대안: `defaults write cc.snapscreen.SnapScreen AppleLanguages '(en)'` 후 실행, 확인 뒤 `defaults delete cc.snapscreen.SnapScreen AppleLanguages`.) 홈/설정/편집기(히스토리로 열기)가 영어인지 — 서브에이전트는 실행·크래시만 확인하고 **육안 확인은 사용자**가 스크린샷으로.
- [ ] **Step 4:** `swift test` 최종 (92개), 전체 커밋 정리 확인.

---

## Self-Review (스펙 대조)

- defaultLocalization en + .strings 리소스 → Task 1 ✓ / L() 헬퍼 → Task 1 Step 2 ✓
- 키 일치·빈 값·모듈 번들 조회 테스트 → Task 1 Step 5 ✓
- Info.plist CFBundleDevelopmentRegion/CFBundleLocalizations → Task 1 Step 4 ✓
- 19개 파일 전수 변환 → Task 2(편집기 6) + Task 3(홈·설정 5) + Task 4(AppCore·Updater·CaptureKit 8+ShortcutKeycaps 확인) ✓ — 각 태스크 잔여 한글 grep으로 누락 차단
- 동적 문자열 포맷 키 규약 → 공통 규약 3 ✓ / 용어 일관성 → 용어집 ✓
- bundle.sh 번들 배포 확인 → Task 1 Step 7 + Task 5 Step 1 ✓
- 양 언어 실행 검증(-AppleLanguages) → Task 5 ✓

## 완료 기준

- `swift test` 92개 통과, 잔여 한글 리터럴 grep 결과가 비대상뿐.
- 배포 번들에 en/ko lproj 포함, 한국어/영어 실행 육안 확인(사용자), 영어 레이아웃 깨짐 없음.
- ko.lproj UTF-8.

## 다음 단계

완료 후 버전 0.13.0 범프(AppInfo+Info.plist 동시) + 릴리스.
