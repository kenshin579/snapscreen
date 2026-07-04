# SnapScreen MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** macOS 메뉴바 상주 스크린샷 캡처 + 주석 편집 앱 (전체/창/영역 캡처 → 주석 편집기 → 클립보드/파일 저장)

**Architecture:** SwiftPM 기반 (Xcode 프로젝트 없음). 로직은 `SnapScreenKit` 라이브러리 타깃(단위 테스트 대상), 실행 파일 `SnapScreen`은 얇은 엔트리포인트. UI는 AppKit(오버레이·캔버스·메뉴바) + SwiftUI(툴바·설정) 하이브리드. 캡처는 ScreenCaptureKit(`SCScreenshotManager`), 전역 단축키는 KeyboardShortcuts 패키지(Carbon 기반, 권한 불필요, 단축키 녹화 UI 포함).

**Tech Stack:** Swift 5.9+, macOS 14+, ScreenCaptureKit, AppKit, SwiftUI, CoreImage(픽셀레이트), [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT)

**중요 규칙:**
- 커밋은 절대 main에 직접 하지 않는다. 아래 Task 0의 feature 브랜치에서 작업한다.
- TCC(화면 기록 권한)는 실행 파일이 아닌 .app 번들에 귀속된다. **캡처 관련 수동 검증은 반드시 `Scripts/bundle.sh`로 만든 .app으로 실행**한다. `swift run`으로 캡처를 테스트하면 권한이 터미널에 귀속되어 오동작한다.
- 좌표계 규약 (전 코드 공통):
  - **화면 포인트 좌표**: Cocoa 전역 좌표, 원점 좌하단 (`NSScreen.frame`, `NSEvent.mouseLocation`)
  - **CG/SCK 좌표**: 디스플레이 로컬, 원점 좌상단, 포인트 단위 (`SCStreamConfiguration.sourceRect`)
  - **이미지 픽셀 좌표**: 캡처 결과 CGImage 기준, 원점 좌하단(CGContext 기본), 픽셀 단위. **주석(Annotation)은 모두 이 좌표계로 저장**한다.

---

## 파일 구조 (완성 시점)

```
snapscreen/
├── Package.swift
├── Resources/Info.plist
├── Scripts/
│   ├── bundle.sh                  # swift build + .app 번들 조립 + ad-hoc 서명
│   └── run.sh                     # bundle.sh 후 open
├── Sources/
│   ├── SnapScreen/main.swift      # 엔트리포인트 (5줄)
│   └── SnapScreenKit/
│       ├── AppCore/
│       │   ├── AppDelegate.swift
│       │   ├── StatusItemController.swift
│       │   ├── MainMenuBuilder.swift
│       │   ├── Hotkeys.swift
│       │   └── CaptureCoordinator.swift
│       ├── CaptureKit/
│       │   ├── CaptureEngine.swift
│       │   └── ScreenCapturePermission.swift
│       ├── SelectionOverlay/
│       │   ├── SelectionOverlayController.swift   # 영역 드래그 선택
│       │   └── WindowPickerController.swift       # 창 클릭 선택
│       ├── Editor/
│       │   ├── EditorWindowController.swift
│       │   ├── EditorState.swift
│       │   ├── CanvasView.swift
│       │   ├── ToolbarView.swift                  # SwiftUI
│       │   ├── Annotation.swift                   # 모델 (AppKit 비의존)
│       │   ├── AnnotationStore.swift              # undo/redo (AppKit 비의존)
│       │   ├── AnnotationHitTester.swift          # (AppKit 비의존)
│       │   ├── AnnotationRenderer.swift           # CG 렌더링 (캔버스/플래튼 공용)
│       │   └── FlattenRenderer.swift
│       ├── Output/
│       │   ├── PNGEncoder.swift
│       │   ├── ClipboardWriter.swift
│       │   ├── FileSaver.swift
│       │   ├── SaveLocationResolver.swift         # (AppKit 비의존)
│       │   └── FilenameFormatter.swift            # (AppKit 비의존)
│       ├── Settings/
│       │   ├── SettingsStore.swift
│       │   ├── SettingsView.swift                 # SwiftUI
│       │   └── SettingsWindowController.swift
│       └── Support/
│           ├── ScreenGeometry.swift               # 좌표 변환 (AppKit 비의존)
│           ├── NSScreen+DisplayID.swift
│           └── Notifier.swift                     # UserNotifications 래퍼
├── Tests/SnapScreenKitTests/
│   ├── FilenameFormatterTests.swift
│   ├── SaveLocationResolverTests.swift
│   ├── ScreenGeometryTests.swift
│   ├── AnnotationStoreTests.swift
│   ├── AnnotationHitTesterTests.swift
│   └── FlattenRendererTests.swift
├── docs/manual-test-checklist.md
├── .github/workflows/{ci.yml, release.yml}
├── LICENSE
└── README.md
```

"AppKit 비의존" 파일들이 단위 테스트의 대상이다. UI·캡처는 각 태스크의 수동 검증 단계로 확인한다.

---

### Task 0: 작업 브랜치 준비

- [ ] **Step 1: 브랜치 생성**

현재 `chore/design-spec` 브랜치에 스펙/플랜 문서가 있다. 여기서 구현 브랜치를 분기한다:

```bash
cd /Users/user/src/workspace_snapscreen/snapscreen
git checkout chore/design-spec
git checkout -b feature/mvp
```

이후 모든 태스크는 `feature/mvp`에서 커밋한다. 완료 후 PR 1개(`feature/mvp` → `main`)를 만든다 (`gh pr create` + HEREDOC).

---

### Task 1: SwiftPM 스캐폴드

**Files:**
- Create: `Package.swift`
- Create: `Sources/SnapScreenKit/Support/AppInfo.swift`
- Create: `Sources/SnapScreen/main.swift`
- Test: `Tests/SnapScreenKitTests/AppInfoTests.swift`

- [ ] **Step 1: Package.swift 작성**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SnapScreen",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")
    ],
    targets: [
        .target(name: "SnapScreenKit", dependencies: ["KeyboardShortcuts"]),
        .executableTarget(name: "SnapScreen", dependencies: ["SnapScreenKit"]),
        .testTarget(name: "SnapScreenKitTests", dependencies: ["SnapScreenKit"])
    ]
)
```

- [ ] **Step 2: 실패하는 테스트 작성** — `Tests/SnapScreenKitTests/AppInfoTests.swift`

```swift
import XCTest
@testable import SnapScreenKit

final class AppInfoTests: XCTestCase {
    func testVersion() {
        XCTAssertFalse(AppInfo.version.isEmpty)
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test`
Expected: 컴파일 에러 — `cannot find 'AppInfo'`

- [ ] **Step 4: 최소 구현** — `Sources/SnapScreenKit/Support/AppInfo.swift`

```swift
public enum AppInfo {
    public static let version = "0.1.0"
    public static let bundleID = "cc.snapscreen.SnapScreen"
}
```

`Sources/SnapScreen/main.swift`:

```swift
import SnapScreenKit

print("SnapScreen \(AppInfo.version)")
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test`
Expected: `Test Suite 'All tests' passed`, 1 test

- [ ] **Step 6: Commit**

```bash
git add Package.swift Package.resolved Sources/ Tests/
git commit -m "feat: SwiftPM 스캐폴드 (SnapScreenKit + 실행 타깃 + 테스트)"
```

---

### Task 2: .app 번들 스크립트

**Files:**
- Create: `Resources/Info.plist`
- Create: `Scripts/bundle.sh`
- Create: `Scripts/run.sh`

- [ ] **Step 1: Info.plist 작성** — `Resources/Info.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>cc.snapscreen.SnapScreen</string>
    <key>CFBundleName</key><string>SnapScreen</string>
    <key>CFBundleExecutable</key><string>SnapScreen</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

`LSUIElement=true`가 독 아이콘 숨김(메뉴바 전용 앱)의 핵심이다.

- [ ] **Step 2: bundle.sh 작성** — `Scripts/bundle.sh`

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="build/SnapScreen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/SnapScreen" "$APP/Contents/MacOS/SnapScreen"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# ad-hoc 서명: TCC 권한 부여에 필요. 재빌드 시 권한 재요청이 필요할 수 있음(알려진 제약)
codesign --force --sign - "$APP"
echo "OK: $APP"
```

`Scripts/run.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/bundle.sh "${1:-debug}"
open build/SnapScreen.app
```

- [ ] **Step 3: 실행 권한 부여 및 검증**

```bash
chmod +x Scripts/bundle.sh Scripts/run.sh
Scripts/bundle.sh
./build/SnapScreen.app/Contents/MacOS/SnapScreen
```

Expected: `OK: build/SnapScreen.app` 후 `SnapScreen 0.1.0` 출력

- [ ] **Step 4: .gitignore에 빌드 산출물 추가 후 Commit**

`.gitignore`에 다음 두 줄 추가 (`.build/`는 기존 `build/` 패턴과 별개):

```
.build/
.swiftpm/
```

```bash
git add Resources/ Scripts/ .gitignore
git commit -m "feat: .app 번들 조립 스크립트 + Info.plist"
```

---

### Task 3: FilenameFormatter (TDD)

**Files:**
- Create: `Sources/SnapScreenKit/Output/FilenameFormatter.swift`
- Test: `Tests/SnapScreenKitTests/FilenameFormatterTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import SnapScreenKit

final class FilenameFormatterTests: XCTestCase {
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        var c = DateComponents()
        (c.year, c.month, c.day, c.hour, c.minute, c.second) = (y, mo, d, h, mi, s)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return cal.date(from: c)!
    }

    func testDefaultPrefix() {
        let f = FilenameFormatter(timeZone: TimeZone(identifier: "Asia/Seoul")!)
        XCTAssertEqual(
            f.filename(for: date(2026, 7, 3, 14, 30, 15)),
            "snapscreen 2026-07-03 14.30.15.png"
        )
    }

    func testCustomPrefix() {
        let f = FilenameFormatter(prefix: "shot", timeZone: TimeZone(identifier: "Asia/Seoul")!)
        XCTAssertEqual(
            f.filename(for: date(2026, 1, 9, 9, 5, 7)),
            "shot 2026-01-09 09.05.07.png"
        )
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter FilenameFormatterTests`
Expected: 컴파일 에러 — `cannot find 'FilenameFormatter'`

- [ ] **Step 3: 구현**

```swift
import Foundation

public struct FilenameFormatter {
    private let prefix: String
    private let formatter: DateFormatter

    public init(prefix: String = "snapscreen", timeZone: TimeZone = .current) {
        self.prefix = prefix
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
    }

    public func filename(for date: Date) -> String {
        "\(prefix) \(formatter.string(from: date)).png"
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter FilenameFormatterTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/SnapScreenKit/Output/ Tests/
git commit -m "feat: 파일명 생성기 (snapscreen yyyy-MM-dd HH.mm.ss.png)"
```

---

### Task 4: SaveLocationResolver (TDD)

시스템 스크린샷 저장 위치(`com.apple.screencapture` 도메인의 `location`)를 따르고, 앱 설정 오버라이드 > 시스템 값 > `~/Desktop` 순으로 폴백한다.

**Files:**
- Create: `Sources/SnapScreenKit/Output/SaveLocationResolver.swift`
- Test: `Tests/SnapScreenKitTests/SaveLocationResolverTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import SnapScreenKit

private struct FakeSystemLocation: SystemLocationReading {
    let value: String?
    func screencaptureLocation() -> String? { value }
}

final class SaveLocationResolverTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: tempDir)
    }

    func testOverrideWins() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: "/tmp"))
        XCTAssertEqual(r.resolve(override: tempDir.path), tempDir.standardizedFileURL)
    }

    func testSystemLocationUsedWhenNoOverride() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: tempDir.path))
        XCTAssertEqual(r.resolve(override: nil), tempDir.standardizedFileURL)
    }

    func testFallsBackToDesktopWhenSystemValueMissing() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: nil))
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
        XCTAssertEqual(r.resolve(override: nil), desktop)
    }

    func testFallsBackWhenDirectoryDoesNotExist() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: "/nonexistent/dir"))
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
        XCTAssertEqual(r.resolve(override: "/also/nonexistent"), desktop)
    }

    func testTildeExpansion() {
        let r = SaveLocationResolver(system: FakeSystemLocation(value: "~/Desktop"))
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
        XCTAssertEqual(r.resolve(override: nil), desktop)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SaveLocationResolverTests`
Expected: 컴파일 에러 — `cannot find 'SystemLocationReading'`

- [ ] **Step 3: 구현**

```swift
import Foundation

public protocol SystemLocationReading {
    func screencaptureLocation() -> String?
}

/// macOS 스크린샷 앱(cmd+shift+5)에서 설정한 저장 위치를 읽는다.
public struct SystemLocationReader: SystemLocationReading {
    public init() {}
    public func screencaptureLocation() -> String? {
        CFPreferencesCopyAppValue("location" as CFString, "com.apple.screencapture" as CFString) as? String
    }
}

public struct SaveLocationResolver {
    private let system: SystemLocationReading
    private let fileManager: FileManager

    public init(system: SystemLocationReading = SystemLocationReader(),
                fileManager: FileManager = .default) {
        self.system = system
        self.fileManager = fileManager
    }

    /// 우선순위: 설정 오버라이드 > 시스템 스크린샷 위치 > ~/Desktop
    public func resolve(override: String?) -> URL {
        for candidate in [override, system.screencaptureLocation()] {
            guard let candidate, !candidate.isEmpty else { continue }
            let path = (candidate as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop").standardizedFileURL
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SaveLocationResolverTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: 저장 위치 결정 (설정 > 시스템 스크린샷 위치 > Desktop)"
```

---

### Task 5: ScreenGeometry 좌표 변환 (TDD)

**Files:**
- Create: `Sources/SnapScreenKit/Support/ScreenGeometry.swift`
- Test: `Tests/SnapScreenKitTests/ScreenGeometryTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import SnapScreenKit

final class ScreenGeometryTests: XCTestCase {
    func testCGRectConversionPrimaryScreen() {
        // 1920x1080 화면(원점 0,0)에서 좌상단 근처 100pt 정사각형
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let selection = CGRect(x: 10, y: 970, width: 100, height: 100) // Cocoa: 좌하단 원점
        let cg = ScreenGeometry.cgRect(fromScreenRect: selection, screenFrame: screen)
        XCTAssertEqual(cg, CGRect(x: 10, y: 10, width: 100, height: 100)) // CG: 좌상단 원점
    }

    func testCGRectConversionSecondaryScreen() {
        // 주 화면 오른쪽에 붙은 보조 화면 (Cocoa 전역 좌표에서 x=1920 시작)
        let screen = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        let selection = CGRect(x: 1920 + 50, y: 0, width: 200, height: 100) // 화면 좌하단
        let cg = ScreenGeometry.cgRect(fromScreenRect: selection, screenFrame: screen)
        XCTAssertEqual(cg, CGRect(x: 50, y: 800, width: 200, height: 100))
    }

    func testPixelSize() {
        let px = ScreenGeometry.pixelSize(pointSize: CGSize(width: 100, height: 50), scale: 2)
        XCTAssertEqual(px, CGSize(width: 200, height: 100))
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ScreenGeometryTests`
Expected: 컴파일 에러 — `cannot find 'ScreenGeometry'`

- [ ] **Step 3: 구현**

```swift
import Foundation

public enum ScreenGeometry {
    /// Cocoa 전역 좌표(원점 좌하단) rect → 해당 디스플레이 로컬 CG 좌표(원점 좌상단)
    /// SCStreamConfiguration.sourceRect가 요구하는 좌표계.
    public static func cgRect(fromScreenRect rect: CGRect, screenFrame: CGRect) -> CGRect {
        CGRect(x: rect.minX - screenFrame.minX,
               y: screenFrame.maxY - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    public static func pixelSize(pointSize: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: pointSize.width * scale, height: pointSize.height * scale)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter ScreenGeometryTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: Cocoa↔CG 좌표 변환 유틸"
```

---

### Task 6: Annotation 모델 + AnnotationStore + HitTester (TDD)

주석은 벡터 객체로, **이미지 픽셀 좌표(원점 좌하단)** 로 저장한다. undo/redo는 스냅샷 방식.

**Files:**
- Create: `Sources/SnapScreenKit/Editor/Annotation.swift`
- Create: `Sources/SnapScreenKit/Editor/AnnotationStore.swift`
- Create: `Sources/SnapScreenKit/Editor/AnnotationHitTester.swift`
- Test: `Tests/SnapScreenKitTests/AnnotationStoreTests.swift`
- Test: `Tests/SnapScreenKitTests/AnnotationHitTesterTests.swift`

- [ ] **Step 1: 모델 실패 테스트 작성** — `AnnotationStoreTests.swift`

```swift
import XCTest
@testable import SnapScreenKit

final class AnnotationStoreTests: XCTestCase {
    private func rect(_ x: CGFloat = 0, _ y: CGFloat = 0) -> Annotation {
        Annotation(kind: .rectangle(CGRect(x: x, y: y, width: 100, height: 50)))
    }

    func testAddAndUndoRedo() {
        let store = AnnotationStore()
        XCTAssertFalse(store.canUndo)

        let a = rect()
        store.add(a)
        XCTAssertEqual(store.annotations, [a])
        XCTAssertTrue(store.canUndo)

        store.undo()
        XCTAssertEqual(store.annotations, [])
        XCTAssertTrue(store.canRedo)

        store.redo()
        XCTAssertEqual(store.annotations, [a])
    }

    func testNewActionClearsRedoStack() {
        let store = AnnotationStore()
        store.add(rect())
        store.undo()
        store.add(rect(10, 10))
        XCTAssertFalse(store.canRedo)
    }

    func testRemove() {
        let store = AnnotationStore()
        let a = rect()
        store.add(a)
        store.remove(id: a.id)
        XCTAssertEqual(store.annotations, [])
        store.undo()
        XCTAssertEqual(store.annotations, [a])
    }

    func testTranslate() {
        let store = AnnotationStore()
        let a = Annotation(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10)))
        store.add(a)
        store.translate(id: a.id, by: CGVector(dx: 5, dy: -3))
        guard case .arrow(let s, let e) = store.annotations[0].kind else {
            return XCTFail("kind changed")
        }
        XCTAssertEqual(s, CGPoint(x: 5, y: -3))
        XCTAssertEqual(e, CGPoint(x: 15, y: 7))
    }

    func testNextStepNumber() {
        let store = AnnotationStore()
        XCTAssertEqual(store.nextStepNumber, 1)
        store.add(Annotation(kind: .stepBadge(center: .zero, number: 1, radius: 14)))
        store.add(Annotation(kind: .stepBadge(center: .zero, number: 2, radius: 14)))
        XCTAssertEqual(store.nextStepNumber, 3)
        // 2번 배지를 지워도 최대값 기준으로 증가한다
        store.remove(id: store.annotations[0].id)
        XCTAssertEqual(store.nextStepNumber, 3)
    }
}
```

- [ ] **Step 2: 히트 테스트 실패 테스트 작성** — `AnnotationHitTesterTests.swift`

```swift
import XCTest
@testable import SnapScreenKit

final class AnnotationHitTesterTests: XCTestCase {
    func testArrowHit() {
        let a = Annotation(kind: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0)))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 5), annotations: [a]))
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 30), annotations: [a]))
    }

    func testRectangleHitsBorderNotInside() {
        let a = Annotation(kind: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 0, y: 50), annotations: [a]))   // 테두리
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 50), annotations: [a]))     // 내부
    }

    func testPixelateHitsInside() {
        let a = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 100, height: 100)))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 50, y: 50), annotations: [a]))
    }

    func testBadgeHit() {
        let a = Annotation(kind: .stepBadge(center: CGPoint(x: 50, y: 50), number: 1, radius: 14))
        XCTAssertNotNil(AnnotationHitTester.hitTest(CGPoint(x: 55, y: 55), annotations: [a]))
        XCTAssertNil(AnnotationHitTester.hitTest(CGPoint(x: 90, y: 90), annotations: [a]))
    }

    func testTopmostWins() {
        let bottom = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 100, height: 100)))
        let top = Annotation(kind: .pixelate(CGRect(x: 40, y: 40, width: 100, height: 100)))
        let hit = AnnotationHitTester.hitTest(CGPoint(x: 50, y: 50), annotations: [bottom, top])
        XCTAssertEqual(hit?.id, top.id)
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test --filter Annotation`
Expected: 컴파일 에러 — `cannot find 'Annotation'`

- [ ] **Step 4: 모델 구현** — `Annotation.swift`

```swift
import Foundation
import CoreGraphics

public enum PaletteColor: String, CaseIterable, Equatable, Codable {
    case red, orange, green, blue, black, white
}

public enum AnnotationKind: Equatable {
    case arrow(start: CGPoint, end: CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case text(origin: CGPoint, string: String, fontSize: CGFloat)
    case pixelate(CGRect)
    case stepBadge(center: CGPoint, number: Int, radius: CGFloat)

    public func translated(by d: CGVector) -> AnnotationKind {
        switch self {
        case .arrow(let s, let e):
            return .arrow(start: CGPoint(x: s.x + d.dx, y: s.y + d.dy),
                          end: CGPoint(x: e.x + d.dx, y: e.y + d.dy))
        case .rectangle(let r): return .rectangle(r.offsetBy(dx: d.dx, dy: d.dy))
        case .ellipse(let r): return .ellipse(r.offsetBy(dx: d.dx, dy: d.dy))
        case .text(let o, let s, let f):
            return .text(origin: CGPoint(x: o.x + d.dx, y: o.y + d.dy), string: s, fontSize: f)
        case .pixelate(let r): return .pixelate(r.offsetBy(dx: d.dx, dy: d.dy))
        case .stepBadge(let c, let n, let r):
            return .stepBadge(center: CGPoint(x: c.x + d.dx, y: c.y + d.dy), number: n, radius: r)
        }
    }

    /// 히트 테스트/다시그리기용 대략적 경계 (이미지 픽셀 좌표)
    public var bounds: CGRect {
        switch self {
        case .arrow(let s, let e):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(s.x - e.x), height: abs(s.y - e.y))
        case .rectangle(let r), .ellipse(let r), .pixelate(let r):
            return r
        case .text(let o, let s, let f):
            // AppKit 없이 근사: 글자폭 0.6em, 높이 1.3em
            return CGRect(x: o.x, y: o.y,
                          width: CGFloat(s.count) * f * 0.6, height: f * 1.3)
        case .stepBadge(let c, _, let r):
            return CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
        }
    }
}

public struct Annotation: Equatable, Identifiable {
    public let id: UUID
    public var kind: AnnotationKind
    public var color: PaletteColor
    public var lineWidth: CGFloat

    public init(id: UUID = UUID(), kind: AnnotationKind,
                color: PaletteColor = .red, lineWidth: CGFloat = 4) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }
}
```

- [ ] **Step 5: 스토어 구현** — `AnnotationStore.swift`

```swift
import Foundation
import CoreGraphics

public final class AnnotationStore {
    public private(set) var annotations: [Annotation] = []
    private var undoStack: [[Annotation]] = []
    private var redoStack: [[Annotation]] = []

    public init() {}

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func add(_ annotation: Annotation) {
        snapshot()
        annotations.append(annotation)
    }

    public func remove(id: UUID) {
        guard annotations.contains(where: { $0.id == id }) else { return }
        snapshot()
        annotations.removeAll { $0.id == id }
    }

    public func translate(id: UUID, by delta: CGVector) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        snapshot()
        annotations[i].kind = annotations[i].kind.translated(by: delta)
    }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(annotations)
        annotations = prev
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(annotations)
        annotations = next
    }

    public var nextStepNumber: Int {
        let numbers = annotations.compactMap { a -> Int? in
            if case .stepBadge(_, let n, _) = a.kind { return n }
            return nil
        }
        return (numbers.max() ?? 0) + 1
    }

    private func snapshot() {
        undoStack.append(annotations)
        redoStack.removeAll()
    }
}
```

- [ ] **Step 6: 히트 테스터 구현** — `AnnotationHitTester.swift`

```swift
import Foundation
import CoreGraphics

public enum AnnotationHitTester {
    /// 위(나중에 그린 것)부터 검사. point는 이미지 픽셀 좌표.
    public static func hitTest(_ point: CGPoint, annotations: [Annotation],
                               tolerance: CGFloat = 8) -> Annotation? {
        annotations.reversed().first { hits(point, $0, tolerance) }
    }

    private static func hits(_ p: CGPoint, _ a: Annotation, _ tol: CGFloat) -> Bool {
        switch a.kind {
        case .arrow(let s, let e):
            return distanceToSegment(p, s, e) <= tol
        case .rectangle(let r), .ellipse(let r):
            // 테두리 스트로크만 잡는다 (내부는 통과 — 아래 주석 선택 가능하게)
            let outer = r.insetBy(dx: -tol, dy: -tol)
            let inner = r.insetBy(dx: tol, dy: tol)
            let insideInner = inner.width > 0 && inner.height > 0 && inner.contains(p)
            return outer.contains(p) && !insideInner
        case .text, .pixelate:
            return a.kind.bounds.insetBy(dx: -tol, dy: -tol).contains(p)
        case .stepBadge(let c, _, let r):
            return hypot(p.x - c.x, p.y - c.y) <= r + tol
        }
    }

    private static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let ab = CGVector(dx: b.x - a.x, dy: b.y - a.y)
        let lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * ab.dx + (p.y - a.y) * ab.dy) / lengthSquared))
        let proj = CGPoint(x: a.x + t * ab.dx, y: a.y + t * ab.dy)
        return hypot(p.x - proj.x, p.y - proj.y)
    }
}
```

- [ ] **Step 7: 테스트 통과 확인**

Run: `swift test`
Expected: PASS (전체, AnnotationStore 6 + HitTester 5 포함)

- [ ] **Step 8: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: 주석 벡터 모델 + undo/redo 스토어 + 히트 테스터"
```

---

### Task 7: CaptureEngine + 화면 기록 권한

ScreenCaptureKit 래퍼. 이 태스크는 빌드 확인까지만 하고, 실제 캡처 동작은 Task 9에서 앱에 연결해 수동 검증한다.

**Files:**
- Create: `Sources/SnapScreenKit/Support/NSScreen+DisplayID.swift`
- Create: `Sources/SnapScreenKit/CaptureKit/ScreenCapturePermission.swift`
- Create: `Sources/SnapScreenKit/CaptureKit/CaptureEngine.swift`

- [ ] **Step 1: NSScreen 확장** — `NSScreen+DisplayID.swift`

```swift
import AppKit

public extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    static func screen(containing point: CGPoint) -> NSScreen? {
        screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
```

- [ ] **Step 2: 권한 관리 구현** — `ScreenCapturePermission.swift`

```swift
import AppKit

@MainActor
public enum ScreenCapturePermission {
    /// 권한이 있으면 true. 없으면 시스템 요청을 트리거하고 안내 알림창을 띄운 뒤 false.
    public static func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess() // 최초 1회만 시스템 프롬프트 발생

        let alert = NSAlert()
        alert.messageText = "화면 기록 권한이 필요합니다"
        alert.informativeText = """
        시스템 설정 > 개인정보 보호 및 보안 > 화면 및 시스템 오디오 녹음에서 \
        SnapScreen을 켠 후, 앱을 다시 실행해 주세요.
        """
        alert.addButton(withTitle: "시스템 설정 열기")
        alert.addButton(withTitle: "닫기")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
            NSWorkspace.shared.open(url)
        }
        return false
    }
}
```

- [ ] **Step 3: 캡처 엔진 구현** — `CaptureEngine.swift`

```swift
import AppKit
import ScreenCaptureKit

public struct CaptureResult {
    public let image: CGImage
    /// 캡처 당시 디스플레이 배율 (PNG DPI 메타데이터, 주석 크기 산정에 사용)
    public let scale: CGFloat
}

public enum CaptureError: LocalizedError {
    case displayNotFound
    public var errorDescription: String? {
        switch self {
        case .displayNotFound: return "캡처할 디스플레이를 찾지 못했습니다."
        }
    }
}

public final class CaptureEngine {
    public init() {}

    /// 전체 화면: point(Cocoa 전역 좌표)가 속한 디스플레이 전체
    public func captureFullDisplay(containing point: CGPoint) async throws -> CaptureResult {
        guard let screen = await NSScreen.screen(containing: point) else {
            throw CaptureError.displayNotFound
        }
        let (displayID, scale) = await (screen.displayID, screen.backingScaleFactor)
        return try await capture(displayID: displayID, sourceRect: nil, scale: scale)
    }

    /// 영역: rect는 디스플레이 로컬 CG 좌표(원점 좌상단, 포인트)
    public func captureArea(rect: CGRect, displayID: CGDirectDisplayID,
                            scale: CGFloat) async throws -> CaptureResult {
        try await capture(displayID: displayID, sourceRect: rect, scale: scale)
    }

    public func captureWindow(_ window: SCWindow, scale: CGFloat) async throws -> CaptureResult {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = configuration(size: window.frame.size, scale: scale)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: config)
        return CaptureResult(image: image, scale: scale)
    }

    /// 창 선택 UI용 창 목록 (일반 레이어의 화면 표시 중인 창만)
    public func shareableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        return content.windows.filter {
            $0.isOnScreen && $0.windowLayer == 0
                && $0.frame.width >= 40 && $0.frame.height >= 40
        }
    }

    private func capture(displayID: CGDirectDisplayID, sourceRect: CGRect?,
                         scale: CGFloat) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        // 우리 앱 창(오버레이 등)은 캡처에서 제외
        let ourWindows = content.windows.filter {
            $0.owningApplication?.processID == pid_t(ProcessInfo.processInfo.processIdentifier)
        }
        let filter = SCContentFilter(display: display, excludingWindows: ourWindows)
        let size = sourceRect?.size ?? CGSize(width: display.width, height: display.height)
        let config = configuration(size: size, scale: scale)
        if let sourceRect { config.sourceRect = sourceRect }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: config)
        return CaptureResult(image: image, scale: scale)
    }

    private func configuration(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let px = ScreenGeometry.pixelSize(pointSize: size, scale: scale)
        config.width = Int(px.width)
        config.height = Int(px.height)
        config.showsCursor = false
        config.captureResolution = .best
        return config
    }
}
```

- [ ] **Step 4: 빌드 및 기존 테스트 통과 확인**

Run: `swift build && swift test`
Expected: 빌드 성공, 기존 테스트 전부 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/
git commit -m "feat: ScreenCaptureKit 캡처 엔진 + 화면 기록 권한 처리"
```

---

### Task 8: 메뉴바 상주 앱

**Files:**
- Modify: `Sources/SnapScreen/main.swift` (전체 교체)
- Create: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`
- Create: `Sources/SnapScreenKit/AppCore/StatusItemController.swift`
- Create: `Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift` (이 태스크에서는 스텁)
- Create: `Sources/SnapScreenKit/AppCore/MainMenuBuilder.swift`

- [ ] **Step 1: main.swift 교체**

```swift
import AppKit
import SnapScreenKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 2: CaptureCoordinator 스텁** — `CaptureCoordinator.swift`

```swift
import AppKit

public enum CaptureMode {
    case area, window, fullScreen
}

@MainActor
public final class CaptureCoordinator {
    public init() {}

    public func beginCapture(_ mode: CaptureMode) {
        // Task 9~11에서 구현. 지금은 메뉴 배선 확인용.
        NSSound.beep()
    }
}
```

- [ ] **Step 3: StatusItemController 구현**

```swift
import AppKit

@MainActor
public final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let coordinator: CaptureCoordinator

    public init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "SnapScreen")
        let menu = NSMenu()
        menu.addItem(item("영역 캡처", #selector(captureArea)))
        menu.addItem(item("창 캡처", #selector(captureWindow)))
        menu.addItem(item("전체 화면 캡처", #selector(captureFullScreen)))
        menu.addItem(.separator())
        menu.addItem(item("설정…", #selector(openSettings)))
        menu.addItem(.separator())
        menu.addItem(item("SnapScreen 종료", #selector(quit)))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func captureArea() { coordinator.beginCapture(.area) }
    @objc private func captureWindow() { coordinator.beginCapture(.window) }
    @objc private func captureFullScreen() { coordinator.beginCapture(.fullScreen) }
    @objc private func openSettings() { /* Task 16 */ }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 4: MainMenuBuilder 구현**

LSUIElement 앱이라도 편집기 창의 `cmd+C`/`cmd+S`/`cmd+Z` 키 이퀴밸런트 라우팅에 메인 메뉴가 필요하다. 액션은 nil-target(응답 체인)으로 두고 편집기 컨트롤러가 구현한다(Task 12, 14).

```swift
import AppKit

@MainActor
public enum MainMenuBuilder {
    public static func install() {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "SnapScreen 종료",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(submenu(appMenu, title: "SnapScreen"))

        let fileMenu = NSMenu(title: "파일")
        fileMenu.addItem(withTitle: "저장…", action: Selector(("saveDocument:")), keyEquivalent: "s")
        fileMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(fileMenu, title: "파일"))

        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: Selector(("undoAction:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "실행 복귀", action: Selector(("redoAction:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "복사", action: Selector(("copyMerged:")), keyEquivalent: "c")
        main.addItem(submenu(editMenu, title: "편집"))

        NSApp.mainMenu = main
    }

    private static func submenu(_ menu: NSMenu, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
```

- [ ] **Step 5: AppDelegate 구현**

```swift
import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator!
    private var statusItemController: StatusItemController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenuBuilder.install()
        coordinator = CaptureCoordinator()
        statusItemController = StatusItemController(coordinator: coordinator)
    }
}
```

- [ ] **Step 6: 수동 검증**

Run: `Scripts/run.sh`
Expected:
- 독에 아이콘이 나타나지 않는다
- 메뉴바에 카메라 아이콘이 나타난다
- 메뉴 클릭 → 캡처 항목 3개 + 설정 + 종료가 보인다
- "영역 캡처" 클릭 → 비프음 (스텁 동작)
- "SnapScreen 종료" → 앱 종료

- [ ] **Step 7: Commit**

```bash
git add Sources/
git commit -m "feat: 메뉴바 상주 앱 (NSStatusItem + 메인 메뉴 + 코디네이터 스텁)"
```

---

### Task 9: 전역 단축키 + 전체 화면 캡처 E2E

첫 번째 실제 캡처. 단축키 → 캡처 → 클립보드 복사 + 파일 저장까지. (편집기는 Task 12에서 연결)

**Files:**
- Create: `Sources/SnapScreenKit/AppCore/Hotkeys.swift`
- Create: `Sources/SnapScreenKit/Settings/SettingsStore.swift`
- Create: `Sources/SnapScreenKit/Output/PNGEncoder.swift`
- Create: `Sources/SnapScreenKit/Output/ClipboardWriter.swift`
- Create: `Sources/SnapScreenKit/Output/FileSaver.swift`
- Create: `Sources/SnapScreenKit/Support/Notifier.swift`
- Modify: `Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift` (전체 교체)
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`

- [ ] **Step 1: 단축키 정의** — `Hotkeys.swift`

기본값: `⌘⇧1` 영역 / `⌘⇧2` 창 / `⌘⇧0` 전체. (`⌘⇧3~6`은 macOS 시스템 스크린샷 단축키라 피한다)

```swift
import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.one, modifiers: [.command, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.two, modifiers: [.command, .shift]))
    static let captureFullScreen = Self("captureFullScreen", default: .init(.zero, modifiers: [.command, .shift]))
}

@MainActor
public enum Hotkeys {
    public static func register(coordinator: CaptureCoordinator) {
        KeyboardShortcuts.onKeyUp(for: .captureArea) { coordinator.beginCapture(.area) }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { coordinator.beginCapture(.window) }
        KeyboardShortcuts.onKeyUp(for: .captureFullScreen) { coordinator.beginCapture(.fullScreen) }
    }
}
```

- [ ] **Step 2: SettingsStore (최소)** — `SettingsStore.swift`

```swift
import Foundation

public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private enum Key {
        static let saveFolderOverride = "saveFolderOverride"
        static let filenamePrefix = "filenamePrefix"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// nil이면 시스템 스크린샷 저장 위치를 따른다
    @Published public var saveFolderOverride: String? {
        didSet { defaults.set(saveFolderOverride, forKey: Key.saveFolderOverride) }
    }
    @Published public var filenamePrefix: String = "snapscreen" {
        didSet { defaults.set(filenamePrefix, forKey: Key.filenamePrefix) }
    }

    public func load() {
        saveFolderOverride = defaults.string(forKey: Key.saveFolderOverride)
        filenamePrefix = defaults.string(forKey: Key.filenamePrefix) ?? "snapscreen"
    }
}
```

- [ ] **Step 3: PNG 인코더 + 클립보드 + 파일 저장**

`PNGEncoder.swift` — Retina DPI 메타데이터를 위해 포인트 크기를 rep에 기록:

```swift
import AppKit

public enum PNGEncoder {
    public static func encode(_ image: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: CGFloat(image.width) / scale,
                          height: CGFloat(image.height) / scale)
        return rep.representation(using: .png, properties: [:])
    }
}
```

`ClipboardWriter.swift`:

```swift
import AppKit

public enum ClipboardWriter {
    @discardableResult
    public static func write(_ image: CGImage, scale: CGFloat) -> Bool {
        guard let data = PNGEncoder.encode(image, scale: scale) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setData(data, forType: .png)
    }
}
```

`FileSaver.swift` — 저장 실패 시 Desktop 폴백:

```swift
import Foundation

public struct FileSaver {
    private let settings: SettingsStore
    private let resolver: SaveLocationResolver

    public init(settings: SettingsStore, resolver: SaveLocationResolver = SaveLocationResolver()) {
        self.settings = settings
        self.resolver = resolver
    }

    public enum Outcome {
        case saved(URL)
        case savedToFallback(URL)
        case failed(Error)
    }

    public func save(_ image: CGImage, scale: CGFloat, date: Date = Date()) -> Outcome {
        guard let data = PNGEncoder.encode(image, scale: scale) else {
            return .failed(CocoaError(.fileWriteUnknown))
        }
        let name = FilenameFormatter(prefix: settings.filenamePrefix).filename(for: date)
        let dir = resolver.resolve(override: settings.saveFolderOverride)
        do {
            let url = dir.appendingPathComponent(name)
            try data.write(to: url)
            return .saved(url)
        } catch {
            let fallback = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop").appendingPathComponent(name)
            do {
                try data.write(to: fallback)
                return .savedToFallback(fallback)
            } catch {
                return .failed(error)
            }
        }
    }
}
```

- [ ] **Step 4: Notifier** — `Notifier.swift`

.app 번들로 실행될 때만 UNUserNotificationCenter가 동작하므로, 번들 실행이 전제다(bundle.sh 실행 규칙).

```swift
import Foundation
import UserNotifications

public enum Notifier {
    public static func requestAuthorization() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert]) { _, _ in }
    }

    public static func show(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 5: CaptureCoordinator 구현 (전체 교체)**

```swift
import AppKit

public enum CaptureMode {
    case area, window, fullScreen
}

@MainActor
public final class CaptureCoordinator {
    private let engine = CaptureEngine()
    public let settings = SettingsStore()

    public init() {
        settings.load()
    }

    public func beginCapture(_ mode: CaptureMode) {
        guard ScreenCapturePermission.ensurePermission() else { return }
        switch mode {
        case .fullScreen:
            let mouse = NSEvent.mouseLocation
            Task {
                do {
                    let result = try await self.engine.captureFullDisplay(containing: mouse)
                    self.handleCaptured(result)
                } catch {
                    Notifier.show(title: "캡처 실패", body: error.localizedDescription)
                }
            }
        case .area:
            break // Task 10
        case .window:
            break // Task 11
        }
    }

    func handleCaptured(_ result: CaptureResult) {
        // Task 12에서 편집기 열기로 교체. 지금은 클립보드 + 파일 저장.
        ClipboardWriter.write(result.image, scale: result.scale)
        switch FileSaver(settings: settings).save(result.image, scale: result.scale) {
        case .saved:
            break
        case .savedToFallback(let url):
            Notifier.show(title: "저장 위치 폴백", body: "데스크탑에 저장했습니다: \(url.lastPathComponent)")
        case .failed(let error):
            Notifier.show(title: "저장 실패", body: error.localizedDescription)
        }
    }
}
```

- [ ] **Step 6: AppDelegate에 배선 추가**

`applicationDidFinishLaunching` 끝에 두 줄 추가:

```swift
        Hotkeys.register(coordinator: coordinator)
        Notifier.requestAuthorization()
```

- [ ] **Step 7: 빌드 + 테스트**

Run: `swift test`
Expected: 전부 PASS

- [ ] **Step 8: 수동 검증 (첫 캡처!)**

Run: `Scripts/run.sh`
Expected:
1. 최초 실행: 메뉴에서 "전체 화면 캡처" 클릭 → 권한 안내 알림창 → "시스템 설정 열기" → SnapScreen 켜기 → 앱 재실행
2. `⌘⇧0` 입력 → (알림 권한 허용) → 시스템 스크린샷 저장 위치(기본 Desktop)에 `snapscreen <날짜>.png` 생김
3. 미리보기 앱에서 `⌘V` 붙여넣기 → 캡처 이미지 확인
4. Retina 디스플레이라면 png 픽셀 크기가 화면 포인트의 2배인지 확인: `sips -g pixelWidth -g pixelHeight <파일>`

- [ ] **Step 9: Commit**

```bash
git add Sources/
git commit -m "feat: 전역 단축키 + 전체 화면 캡처 → 클립보드/파일 저장 E2E"
```

---

### Task 10: 영역 선택 오버레이 + 영역 캡처

**Files:**
- Create: `Sources/SnapScreenKit/SelectionOverlay/SelectionOverlayController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift` (`.area` 케이스)

- [ ] **Step 1: 오버레이 구현** — `SelectionOverlayController.swift`

디스플레이마다 borderless 패널 1개. 드래그는 시작한 디스플레이 안으로 제한(뷰 bounds가 자연히 제한한다). `esc` 취소.

```swift
import AppKit

@MainActor
public final class SelectionOverlayController {
    public struct Selection {
        public let rectInScreenPoints: CGRect // Cocoa 전역 좌표
        public let screen: NSScreen
    }

    private var panels: [OverlayPanel] = []
    private var completion: ((Selection?) -> Void)?

    public init() {}

    public func begin(completion: @escaping (Selection?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen) { [weak self] selection in
                self?.finish(with: selection)
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        (panels.first { NSMouseInRect(mouse, $0.overlayScreen.frame, false) } ?? panels.first)?
            .makeKey()
    }

    private func finish(with selection: Selection?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        let done = completion
        completion = nil
        done?(selection)
    }
}

private final class OverlayPanel: NSPanel {
    let overlayScreen: NSScreen

    init(screen: NSScreen, onFinish: @escaping (SelectionOverlayController.Selection?) -> Void) {
        overlayScreen = screen
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = SelectionView(screen: screen, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionView: NSView {
    private let screen: NSScreen
    private let onFinish: (SelectionOverlayController.Selection?) -> Void
    private var dragStart: CGPoint?
    private var selectionRect: CGRect?

    init(screen: NSScreen, onFinish: @escaping (SelectionOverlayController.Selection?) -> Void) {
        self.screen = screen
        self.onFinish = onFinish
        super.init(frame: screen.frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // esc
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        window?.makeKey()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                               width: abs(start.x - p.x), height: abs(start.y - p.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; selectionRect = nil }
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else {
            onFinish(nil) // 클릭만 하면 취소
            return
        }
        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        onFinish(.init(rectInScreenPoints: global, screen: screen))
    }

    override func draw(_ dirtyRect: NSRect) {
        // 어둡게 깔고 선택 영역만 뚫는다
        NSColor(white: 0, alpha: 0.35).setFill()
        let dim = NSBezierPath(rect: bounds)
        if let rect = selectionRect {
            dim.appendRect(rect)
            dim.windingRule = .evenOdd
        }
        dim.fill()

        guard let rect = selectionRect else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        // 크기 라벨 (픽셀 단위)
        let scale = screen.backingScaleFactor
        let label = "\(Int(rect.width * scale)) × \(Int(rect.height * scale)) px" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(white: 0, alpha: 0.7)
        ]
        var origin = CGPoint(x: rect.maxX + 8, y: rect.minY - 20)
        let size = label.size(withAttributes: attrs)
        origin.x = min(origin.x, bounds.maxX - size.width - 4)
        origin.y = max(origin.y, 4)
        label.draw(at: origin, withAttributes: attrs)
    }
}
```

- [ ] **Step 2: 코디네이터 `.area` 케이스 구현**

`CaptureCoordinator`에 프로퍼티 추가:

```swift
    private var overlay: SelectionOverlayController?
```

`beginCapture`의 `case .area:`를 다음으로 교체:

```swift
        case .area:
            guard overlay == nil else { return } // 중복 실행 방지
            let overlayController = SelectionOverlayController()
            overlay = overlayController
            overlayController.begin { [weak self] selection in
                guard let self else { return }
                self.overlay = nil
                guard let selection else { return }
                let cgRect = ScreenGeometry.cgRect(
                    fromScreenRect: selection.rectInScreenPoints,
                    screenFrame: selection.screen.frame)
                let displayID = selection.screen.displayID
                let scale = selection.screen.backingScaleFactor
                Task {
                    do {
                        let result = try await self.engine.captureArea(
                            rect: cgRect, displayID: displayID, scale: scale)
                        self.handleCaptured(result)
                    } catch {
                        Notifier.show(title: "캡처 실패", body: error.localizedDescription)
                    }
                }
            }
```

- [ ] **Step 3: 빌드 + 테스트**

Run: `swift test`
Expected: 전부 PASS

- [ ] **Step 4: 수동 검증**

Run: `Scripts/run.sh`
Expected:
1. `⌘⇧1` → 전 화면이 어두워지고 십자선 커서
2. 드래그 → 선택 영역이 밝아지고 테두리 + `W × H px` 라벨
3. 놓으면 → 저장 위치에 png 생성, 클립보드에도 복사. **이미지가 화면에서 선택한 그 영역과 픽셀 단위로 일치하는지 확인** (특히 Retina + 보조 모니터)
4. `esc` 또는 클릭만 → 취소, 캡처 없음
5. 멀티 모니터: 보조 화면에서 드래그 → 보조 화면 영역이 정확히 캡처됨

- [ ] **Step 5: Commit**

```bash
git add Sources/
git commit -m "feat: 영역 선택 오버레이 + 영역 캡처"
```

---

### Task 11: 창 선택 + 창 캡처

**Files:**
- Create: `Sources/SnapScreenKit/SelectionOverlay/WindowPickerController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift` (`.window` 케이스)

- [ ] **Step 1: 창 선택 오버레이 구현** — `WindowPickerController.swift`

창 목록은 SCK에서 받고(frame은 CG 좌표), Cocoa 전역 좌표로 변환해 마우스 아래 창을 하이라이트한다.

```swift
import AppKit
import ScreenCaptureKit

@MainActor
public final class WindowPickerController {
    public struct PickTarget {
        public let window: SCWindow
        public let frameInScreenPoints: CGRect
    }

    private var panels: [PickerPanel] = []
    private var completion: ((PickTarget?) -> Void)?
    private var targets: [PickTarget] = []

    public init() {}

    /// windows: CaptureEngine.shareableWindows() 결과 (앞쪽 창이 배열 앞)
    public func begin(windows: [SCWindow], completion: @escaping (PickTarget?) -> Void) {
        self.completion = completion
        // CG 전역 좌표(주 화면 좌상단 원점) → Cocoa 전역 좌표
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        targets = windows.map { w in
            let f = w.frame
            let cocoa = CGRect(x: f.minX, y: primaryHeight - f.maxY,
                               width: f.width, height: f.height)
            return PickTarget(window: w, frameInScreenPoints: cocoa)
        }
        for screen in NSScreen.screens {
            let panel = PickerPanel(screen: screen, targets: targets) { [weak self] target in
                self?.finish(with: target)
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        (panels.first { NSMouseInRect(mouse, $0.frame, false) } ?? panels.first)?.makeKey()
    }

    private func finish(with target: PickTarget?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        let done = completion
        completion = nil
        done?(target)
    }
}

private final class PickerPanel: NSPanel {
    init(screen: NSScreen, targets: [WindowPickerController.PickTarget],
         onFinish: @escaping (WindowPickerController.PickTarget?) -> Void) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        acceptsMouseMovedEvents = true
        contentView = PickerView(screen: screen, targets: targets, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    private let screen: NSScreen
    private let targets: [WindowPickerController.PickTarget]
    private let onFinish: (WindowPickerController.PickTarget?) -> Void
    private var hovered: WindowPickerController.PickTarget?
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen, targets: [WindowPickerController.PickTarget],
         onFinish: @escaping (WindowPickerController.PickTarget?) -> Void) {
        self.screen = screen
        self.targets = targets
        self.onFinish = onFinish
        super.init(frame: screen.frame)
        updateHover(at: NSEvent.mouseLocation)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // esc
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: NSEvent.mouseLocation)
    }

    private func updateHover(at globalPoint: CGPoint) {
        // targets는 앞 창부터 정렬되어 있으므로 첫 매치가 최전면 창
        hovered = targets.first { $0.frameInScreenPoints.contains(globalPoint) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onFinish(hovered)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.35).setFill()
        bounds.fill()
        guard let hovered else { return }
        // 전역 좌표 → 이 화면 로컬 좌표
        let local = hovered.frameInScreenPoints
            .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            .intersection(bounds)
        guard !local.isEmpty else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        local.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: local)
        path.lineWidth = 2
        path.stroke()
    }
}
```

- [ ] **Step 2: 코디네이터 `.window` 케이스 구현**

프로퍼티 추가:

```swift
    private var windowPicker: WindowPickerController?
```

`case .window:`를 다음으로 교체:

```swift
        case .window:
            guard windowPicker == nil else { return }
            Task {
                do {
                    let windows = try await self.engine.shareableWindows()
                    let picker = WindowPickerController()
                    self.windowPicker = picker
                    picker.begin(windows: windows) { [weak self] target in
                        guard let self else { return }
                        self.windowPicker = nil
                        guard let target else { return }
                        let scale = NSScreen.screen(
                            containing: CGPoint(x: target.frameInScreenPoints.midX,
                                                y: target.frameInScreenPoints.midY)
                        )?.backingScaleFactor ?? 2
                        Task {
                            do {
                                let result = try await self.engine.captureWindow(target.window, scale: scale)
                                self.handleCaptured(result)
                            } catch {
                                Notifier.show(title: "캡처 실패", body: error.localizedDescription)
                            }
                        }
                    }
                } catch {
                    Notifier.show(title: "캡처 실패", body: error.localizedDescription)
                }
            }
```

- [ ] **Step 3: 빌드 + 테스트**

Run: `swift test`
Expected: 전부 PASS

- [ ] **Step 4: 수동 검증**

Run: `Scripts/run.sh`
Expected:
1. `⌘⇧2` → 화면이 어두워지고, 마우스를 움직이면 아래 창이 파랗게 하이라이트
2. 겹친 창에서는 최전면 창이 하이라이트
3. 클릭 → 해당 창만 캡처된 png 생성 (그림자 없이 창 내용)
4. `esc` → 취소

- [ ] **Step 5: Commit**

```bash
git add Sources/
git commit -m "feat: 창 선택 오버레이 + 창 캡처"
```

---

### Task 12: 편집기 뼈대 (이미지 표시 + 복사/저장 + 플래튼)

캡처 결과가 저장 대신 **편집기 창으로 열리도록 전환**한다. 이 태스크에서 캔버스는 이미지만 그린다(도구는 Task 13~14).

**Files:**
- Create: `Sources/SnapScreenKit/Editor/FlattenRenderer.swift`
- Create: `Sources/SnapScreenKit/Editor/AnnotationRenderer.swift` (이 태스크에서는 뼈대)
- Create: `Sources/SnapScreenKit/Editor/EditorState.swift`
- Create: `Sources/SnapScreenKit/Editor/CanvasView.swift` (이 태스크에서는 이미지만)
- Create: `Sources/SnapScreenKit/Editor/EditorWindowController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift` (`handleCaptured` 교체)
- Test: `Tests/SnapScreenKitTests/FlattenRendererTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성** — `FlattenRendererTests.swift`

```swift
import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class FlattenRendererTests: XCTestCase {
    private func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testFlattenPreservesDimensions() {
        let base = makeImage(width: 200, height: 100)
        let out = FlattenRenderer.flatten(image: base, annotations: [])
        XCTAssertEqual(out?.width, 200)
        XCTAssertEqual(out?.height, 100)
    }

    func testFlattenWithAnnotationPreservesDimensions() {
        let base = makeImage(width: 200, height: 100)
        let a = Annotation(kind: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 30)))
        let out = FlattenRenderer.flatten(image: base, annotations: [a])
        XCTAssertEqual(out?.width, 200)
        XCTAssertEqual(out?.height, 100)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter FlattenRendererTests`
Expected: 컴파일 에러 — `cannot find 'FlattenRenderer'`

- [ ] **Step 3: AnnotationRenderer 뼈대** — `AnnotationRenderer.swift`

Task 13에서 케이스별 렌더링을 채운다. 지금은 컴파일되는 최소 형태:

```swift
import AppKit
import CoreImage

public extension PaletteColor {
    var nsColor: NSColor {
        switch self {
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .green: return .systemGreen
        case .blue: return .systemBlue
        case .black: return .black
        case .white: return .white
        }
    }
}

/// 이미지 픽셀 좌표(원점 좌하단) CGContext에 주석을 그린다.
/// 캔버스 실시간 표시와 플래튼 내보내기가 공용으로 사용.
public enum AnnotationRenderer {
    public static func draw(_ annotations: [Annotation], in ctx: CGContext, baseImage: CGImage) {
        for annotation in annotations {
            draw(annotation, in: ctx, baseImage: baseImage)
        }
    }

    public static func draw(_ annotation: Annotation, in ctx: CGContext, baseImage: CGImage) {
        // Task 13에서 구현
    }
}
```

- [ ] **Step 4: FlattenRenderer 구현** — `FlattenRenderer.swift`

```swift
import AppKit

public enum FlattenRenderer {
    public static func flatten(image: CGImage, annotations: [Annotation]) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        // 텍스트 렌더링(NSAttributedString.draw)이 현재 NSGraphicsContext를 요구한다
        let nsContext = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        AnnotationRenderer.draw(annotations, in: ctx, baseImage: image)
        NSGraphicsContext.restoreGraphicsState()

        return ctx.makeImage()
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter FlattenRendererTests`
Expected: PASS (2 tests)

- [ ] **Step 6: EditorState** — `EditorState.swift`

```swift
import Foundation

public enum EditorTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, ellipse, text, pixelate, stepBadge
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .arrow: return "화살표"
        case .rectangle: return "사각형"
        case .ellipse: return "원"
        case .text: return "텍스트"
        case .pixelate: return "블러"
        case .stepBadge: return "번호"
        }
    }

    public var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .pixelate: return "mosaic"
        case .stepBadge: return "1.circle"
        }
    }
}

@MainActor
public final class EditorState: ObservableObject {
    @Published public var tool: EditorTool = .arrow
    @Published public var color: PaletteColor = .red
    public init() {}
}
```

- [ ] **Step 7: CanvasView (이미지 표시만)** — `CanvasView.swift`

```swift
import AppKit

@MainActor
public final class CanvasView: NSView {
    let image: CGImage
    let captureScale: CGFloat
    let store: AnnotationStore
    let state: EditorState
    var selectedID: UUID?

    /// 뷰 포인트 → 이미지 픽셀 배율
    var fitScale: CGFloat {
        bounds.width / CGFloat(image.width)
    }

    public init(image: CGImage, captureScale: CGFloat, store: AnnotationStore, state: EditorState) {
        self.image = image
        self.captureScale = captureScale
        self.store = store
        self.state = state
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var acceptsFirstResponder: Bool { true }

    func imagePoint(from event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / fitScale, y: p.y / fitScale)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: fitScale, y: fitScale)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        AnnotationRenderer.draw(store.annotations, in: ctx, baseImage: image)
        drawOverlays(in: ctx) // Task 14에서 드래프트/선택 표시 확장
        ctx.restoreGState()
    }

    func drawOverlays(in ctx: CGContext) {
        // Task 14에서 구현
    }
}
```

- [ ] **Step 8: EditorWindowController** — `EditorWindowController.swift`

창 크기는 이미지 포인트 크기(픽셀/배율)를 화면의 80% 이내로 맞춘다. 툴바는 Task 15에서 추가.

```swift
import AppKit

@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let result: CaptureResult
    private let settings: SettingsStore
    private let store = AnnotationStore()
    private let state = EditorState()
    private var canvas: CanvasView!
    private var onClose: (() -> Void)?

    public init(result: CaptureResult, settings: SettingsStore, onClose: (() -> Void)? = nil) {
        self.result = result
        self.settings = settings
        self.onClose = onClose

        let pointSize = CGSize(width: CGFloat(result.image.width) / result.scale,
                               height: CGFloat(result.image.height) / result.scale)
        let maxSize = NSScreen.main.map { CGSize(width: $0.visibleFrame.width * 0.8,
                                                 height: $0.visibleFrame.height * 0.8) }
            ?? CGSize(width: 1200, height: 800)
        let fit = min(1, maxSize.width / pointSize.width, maxSize.height / pointSize.height)
        let contentSize = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SnapScreen"
        window.contentAspectRatio = pointSize
        super.init(window: window)

        canvas = CanvasView(image: result.image, captureScale: result.scale,
                            store: store, state: state)
        window.contentView = canvas
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func windowWillClose(_ notification: Notification) {
        onClose?() // 스펙: 닫으면 경고 없이 폐기
        onClose = nil
    }

    private func flattened() -> CGImage? {
        FlattenRenderer.flatten(image: result.image, annotations: store.annotations)
    }

    // MARK: - 메인 메뉴 액션 (MainMenuBuilder의 nil-target 셀렉터가 응답 체인으로 도달)

    @objc public func copyMerged(_ sender: Any?) {
        guard let image = flattened() else { return }
        ClipboardWriter.write(image, scale: result.scale)
    }

    @objc public func saveDocument(_ sender: Any?) {
        guard let image = flattened() else { return }
        switch FileSaver(settings: settings).save(image, scale: result.scale) {
        case .saved, .savedToFallback:
            window?.close()
        case .failed(let error):
            Notifier.show(title: "저장 실패", body: error.localizedDescription)
        }
    }

    @objc public func undoAction(_ sender: Any?) {
        store.undo()
        canvas.needsDisplay = true
    }

    @objc public func redoAction(_ sender: Any?) {
        store.redo()
        canvas.needsDisplay = true
    }
}
```

- [ ] **Step 9: 코디네이터 연결 — `handleCaptured` 교체**

`CaptureCoordinator`에 프로퍼티 추가:

```swift
    private var editors: [EditorWindowController] = []
```

`handleCaptured`를 다음으로 교체:

```swift
    func handleCaptured(_ result: CaptureResult) {
        var controller: EditorWindowController?
        controller = EditorWindowController(result: result, settings: settings) { [weak self] in
            self?.editors.removeAll { $0 === controller }
        }
        if let controller { editors.append(controller) }
    }
```

- [ ] **Step 10: 빌드 + 테스트 + 수동 검증**

Run: `swift test && Scripts/run.sh`
Expected:
1. `⌘⇧1`로 영역 캡처 → 편집기 창이 뜨고 캡처 이미지가 실제 크기(포인트)로 보임
2. 큰 영역 캡처 → 창이 화면 80% 이내로 축소되어 표시
3. `⌘C` → 미리보기에 붙여넣기 가능; `⌘S` → 파일 저장 후 창 닫힘
4. `⌘W` → 저장 없이 닫힘 (경고 없음)
5. 연속 캡처 → 편집기 창이 여러 개 동시에 뜸

- [ ] **Step 11: Commit**

```bash
git add Sources/ Tests/
git commit -m "feat: 주석 편집기 뼈대 (캡처→편집기 창, 복사/저장, 플래튼)"
```

---

### Task 13: AnnotationRenderer — 도형 5종 렌더링

**Files:**
- Modify: `Sources/SnapScreenKit/Editor/AnnotationRenderer.swift` (draw(annotation:) 구현)

- [ ] **Step 1: 렌더러 구현**

`AnnotationRenderer`의 `draw(_ annotation:in:baseImage:)`와 보조 메서드를 다음으로 교체/추가:

```swift
    public static func draw(_ annotation: Annotation, in ctx: CGContext, baseImage: CGImage) {
        let color = annotation.color.nsColor.cgColor
        switch annotation.kind {
        case .arrow(let start, let end):
            drawArrow(from: start, to: end, color: color,
                      lineWidth: annotation.lineWidth, in: ctx)
        case .rectangle(let rect):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.stroke(rect)
        case .ellipse(let rect):
            ctx.setStrokeColor(color)
            ctx.setLineWidth(annotation.lineWidth)
            ctx.strokeEllipse(in: rect)
        case .text(let origin, let string, let fontSize):
            drawText(string, at: origin, fontSize: fontSize,
                     color: annotation.color.nsColor, in: ctx)
        case .pixelate(let rect):
            if let pixelated = pixelatedImage(from: baseImage, rect: rect) {
                ctx.draw(pixelated, in: rect)
            }
        case .stepBadge(let center, let number, let radius):
            drawBadge(number: number, center: center, radius: radius,
                      color: annotation.color.nsColor, in: ctx)
        }
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint,
                                  color: CGColor, lineWidth: CGFloat, in ctx: CGContext) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(lineWidth * 4, 16)
        // 몸통은 화살촉 밑까지만
        let bodyEnd = CGPoint(x: end.x - cos(angle) * headLength * 0.8,
                              y: end.y - sin(angle) * headLength * 0.8)
        ctx.setStrokeColor(color)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addLine(to: bodyEnd)
        ctx.strokePath()

        let headAngle: CGFloat = .pi / 7
        let left = CGPoint(x: end.x - cos(angle - headAngle) * headLength,
                           y: end.y - sin(angle - headAngle) * headLength)
        let right = CGPoint(x: end.x - cos(angle + headAngle) * headLength,
                            y: end.y - sin(angle + headAngle) * headLength)
        ctx.setFillColor(color)
        ctx.move(to: end)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat,
                                 color: NSColor, in ctx: CGContext) {
        // 현재 NSGraphicsContext가 이 ctx를 감싸도록 보장 (CanvasView.draw 안에서는 이미 그렇고,
        // FlattenRenderer도 설정해 준다)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: color
        ]
        NSAttributedString(string: string, attributes: attrs).draw(at: origin)
    }

    private static let ciContext = CIContext()

    static func pixelatedImage(from base: CGImage, rect: CGRect) -> CGImage? {
        let clamped = rect.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !clamped.isEmpty else { return nil }
        let input = CIImage(cgImage: base).cropped(to: clamped)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        // 복원 공격 방지: 영역이 커도 블록이 충분히 크도록
        let blockSize = max(12, clamped.width / 24, clamped.height / 24)
        filter.setValue(blockSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: clamped.midX, y: clamped.midY), forKey: kCIInputCenterKey)
        guard let output = filter.outputImage?.cropped(to: clamped) else { return nil }
        return ciContext.createCGImage(output, from: clamped)
    }

    private static func drawBadge(number: Int, center: CGPoint, radius: CGFloat,
                                  color: NSColor, in ctx: CGContext) {
        let circle = CGRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: circle)

        let label = "\(number)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: radius * 1.1),
            .foregroundColor: color == .white ? NSColor.black : NSColor.white
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: CGPoint(x: center.x - size.width / 2,
                               y: center.y - size.height / 2),
                   withAttributes: attrs)
    }
```

- [ ] **Step 2: 빌드 + 테스트**

Run: `swift test`
Expected: 전부 PASS (FlattenRenderer 테스트가 이제 실제 렌더링 경로를 통과)

- [ ] **Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: 주석 렌더러 (화살표/사각형/원/텍스트/픽셀레이트/배지)"
```

---

### Task 14: CanvasView 인터랙션 — 그리기/선택/이동/삭제/텍스트 입력

**Files:**
- Modify: `Sources/SnapScreenKit/Editor/CanvasView.swift`

- [ ] **Step 1: 인터랙션 상태와 마우스 핸들러 추가**

`CanvasView`에 다음을 추가한다:

```swift
    private enum DragMode {
        case none
        case drawing(start: CGPoint)
        case moving(id: UUID, last: CGPoint, total: CGVector)
    }
    private var dragMode: DragMode = .none
    private var draft: Annotation?
    private var textField: NSTextField?
    private var pendingTextOrigin: CGPoint?

    /// 캡처 배율 기준 기본 크기 (Retina에서 주석이 너무 얇아지지 않게)
    private var defaultLineWidth: CGFloat { 3 * captureScale }
    private var defaultFontSize: CGFloat { 16 * captureScale }
    private var badgeRadius: CGFloat { 14 * captureScale }

    public override func mouseDown(with event: NSEvent) {
        commitTextFieldIfNeeded()
        let p = imagePoint(from: event)

        if let hit = AnnotationHitTester.hitTest(p, annotations: store.annotations,
                                                 tolerance: 8 * captureScale) {
            selectedID = hit.id
            dragMode = .moving(id: hit.id, last: p, total: .zero)
            needsDisplay = true
            return
        }
        selectedID = nil

        switch state.tool {
        case .text:
            beginTextInput(at: p, viewPoint: convert(event.locationInWindow, from: nil))
        case .stepBadge:
            store.add(Annotation(kind: .stepBadge(center: p, number: store.nextStepNumber,
                                                  radius: badgeRadius),
                                 color: state.color, lineWidth: defaultLineWidth))
            needsDisplay = true
        default:
            dragMode = .drawing(start: p)
        }
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(from: event)
        switch dragMode {
        case .drawing(let start):
            draft = makeDraft(from: start, to: p)
            needsDisplay = true
        case .moving(let id, let last, let total):
            let delta = CGVector(dx: p.x - last.x, dy: p.y - last.y)
            dragMode = .moving(id: id, last: p,
                               total: CGVector(dx: total.dx + delta.dx, dy: total.dy + delta.dy))
            needsDisplay = true
        case .none:
            break
        }
    }

    public override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .drawing:
            if let draft, draft.kind.bounds.width >= 3 || draft.kind.bounds.height >= 3 {
                store.add(draft)
            }
            draft = nil
        case .moving(let id, _, let total):
            if total.dx != 0 || total.dy != 0 {
                store.translate(id: id, by: total) // undo 1회로 커밋
            }
        case .none:
            break
        }
        dragMode = .none
        needsDisplay = true
    }

    private func makeDraft(from start: CGPoint, to p: CGPoint) -> Annotation {
        let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                          width: abs(start.x - p.x), height: abs(start.y - p.y))
        let kind: AnnotationKind
        switch state.tool {
        case .arrow: kind = .arrow(start: start, end: p)
        case .rectangle: kind = .rectangle(rect)
        case .ellipse: kind = .ellipse(rect)
        case .pixelate: kind = .pixelate(rect)
        case .text, .stepBadge: kind = .rectangle(rect) // 도달하지 않음 (mouseDown에서 처리)
        }
        return Annotation(kind: kind, color: state.color, lineWidth: defaultLineWidth)
    }
```

- [ ] **Step 2: 이동 미리보기와 선택 표시 — `drawOverlays` 교체 + draw 수정**

이동 중에는 원본 대신 이동된 사본을 그린다. `draw(_:)`의 `AnnotationRenderer.draw(store.annotations, ...)` 호출을 다음으로 교체:

```swift
        for annotation in store.annotations {
            if case .moving(let id, _, let total) = dragMode, annotation.id == id {
                var moved = annotation
                moved.kind = annotation.kind.translated(by: total)
                AnnotationRenderer.draw(moved, in: ctx, baseImage: image)
            } else {
                AnnotationRenderer.draw(annotation, in: ctx, baseImage: image)
            }
        }
```

`drawOverlays`를 다음으로 교체:

```swift
    func drawOverlays(in ctx: CGContext) {
        if let draft {
            AnnotationRenderer.draw(draft, in: ctx, baseImage: image)
        }
        if let selectedID,
           let selected = store.annotations.first(where: { $0.id == selectedID }) {
            var bounds = selected.kind.bounds
            if case .moving(let id, _, let total) = dragMode, id == selectedID {
                bounds = bounds.offsetBy(dx: total.dx, dy: total.dy)
            }
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5 * captureScale)
            ctx.setLineDash(phase: 0, lengths: [4 * captureScale, 4 * captureScale])
            ctx.stroke(bounds.insetBy(dx: -6 * captureScale, dy: -6 * captureScale))
            ctx.setLineDash(phase: 0, lengths: [])
        }
    }
```

- [ ] **Step 3: 키 입력 (삭제/esc/도구 단축키) 추가**

```swift
    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            if let selectedID {
                store.remove(id: selectedID)
                self.selectedID = nil
                needsDisplay = true
            }
        case 53: // esc
            selectedID = nil
            needsDisplay = true
        default:
            guard let char = event.charactersIgnoringModifiers?.lowercased() else {
                return super.keyDown(with: event)
            }
            let mapping: [String: EditorTool] = [
                "a": .arrow, "r": .rectangle, "o": .ellipse,
                "t": .text, "b": .pixelate, "n": .stepBadge
            ]
            if let tool = mapping[char] {
                state.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }
```

- [ ] **Step 4: 인라인 텍스트 입력 추가**

```swift
    private func beginTextInput(at imageOrigin: CGPoint, viewPoint: CGPoint) {
        let field = NSTextField(frame: CGRect(x: viewPoint.x, y: viewPoint.y - 22,
                                              width: 220, height: 24))
        field.font = .boldSystemFont(ofSize: 16)
        field.textColor = state.color.nsColor
        field.backgroundColor = NSColor(white: 1, alpha: 0.85)
        field.isBordered = true
        field.focusRingType = .none
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        pendingTextOrigin = imageOrigin
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitTextFieldIfNeeded()
    }

    private func commitTextFieldIfNeeded() {
        guard let field = textField, let origin = pendingTextOrigin else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespaces)
        field.removeFromSuperview()
        textField = nil
        pendingTextOrigin = nil
        if !string.isEmpty {
            store.add(Annotation(kind: .text(origin: origin, string: string,
                                             fontSize: defaultFontSize),
                                 color: state.color, lineWidth: defaultLineWidth))
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
```

- [ ] **Step 5: 빌드 + 테스트**

Run: `swift test`
Expected: 전부 PASS

- [ ] **Step 6: 수동 검증**

Run: `Scripts/run.sh` 후 영역 캡처(`⌘⇧1`)로 편집기 열기:
1. 드래그 → 빨간 화살표. `r`/`o`/`b` 키로 도구 전환 후 각각 사각형/원/모자이크 그리기
2. 모자이크 영역의 글자가 판독 불가능한지 확인
3. `t` → 클릭 → 텍스트 입력 → Enter → 텍스트 주석 생성
4. `n` → 클릭 3번 → ①②③ 배지 자동 증가
5. 화살표 클릭 → 점선 선택 표시 → 드래그 이동 → `⌘Z` → 이동 취소 (1회에 복귀) → `⌘Z` 반복 → 전부 취소 → `⌘⇧Z` 복귀
6. 주석 선택 후 `delete` → 삭제
7. `⌘C` → 미리보기 붙여넣기 → 주석이 이미지에 합쳐져 있음
8. `⌘S` → 저장된 파일에도 주석 포함

- [ ] **Step 7: Commit**

```bash
git add Sources/
git commit -m "feat: 캔버스 인터랙션 (그리기/선택/이동/삭제/텍스트 입력/도구 단축키)"
```

---

### Task 15: 툴바 UI (SwiftUI) + 색상 팔레트

**Files:**
- Create: `Sources/SnapScreenKit/Editor/ToolbarView.swift`
- Modify: `Sources/SnapScreenKit/Editor/EditorWindowController.swift` (레이아웃 변경)

- [ ] **Step 1: ToolbarView 구현**

```swift
import SwiftUI

public struct ToolbarView: View {
    @ObservedObject var state: EditorState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    public init(state: EditorState, onUndo: @escaping () -> Void, onRedo: @escaping () -> Void,
                onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.state = state
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onCopy = onCopy
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: $state.tool) {
                ForEach(EditorTool.allCases) { tool in
                    Image(systemName: tool.symbolName)
                        .help(tool.label)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                ForEach(PaletteColor.allCases, id: \.self) { color in
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(
                            state.color == color ? Color.accentColor : Color.gray.opacity(0.4),
                            lineWidth: state.color == color ? 2 : 1))
                        .onTapGesture { state.color = color }
                }
            }

            Divider().frame(height: 20)

            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .help("실행 취소 (⌘Z)")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                .help("실행 복귀 (⇧⌘Z)")

            Spacer()

            Button(action: onCopy) { Label("복사", systemImage: "doc.on.doc") }
                .help("클립보드로 복사 (⌘C)")
            Button(action: onSave) { Label("저장", systemImage: "square.and.arrow.down") }
                .help("파일로 저장 (⌘S)")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}
```

- [ ] **Step 2: EditorWindowController 레이아웃 변경**

`init`에서 `window.contentView = canvas` 부분을 다음으로 교체 (창 높이에 툴바 44pt 반영):

```swift
        let toolbarHeight: CGFloat = 44
        window.setContentSize(CGSize(width: contentSize.width,
                                     height: contentSize.height + toolbarHeight))
        window.contentAspectRatio = .zero // 툴바 포함이라 비율 고정 해제

        canvas = CanvasView(image: result.image, captureScale: result.scale,
                            store: store, state: state)
        let toolbar = NSHostingView(rootView: ToolbarView(
            state: state,
            onUndo: { [weak self] in self?.undoAction(nil) },
            onRedo: { [weak self] in self?.redoAction(nil) },
            onCopy: { [weak self] in self?.copyMerged(nil) },
            onSave: { [weak self] in self?.saveDocument(nil) }
        ))

        let container = NSView()
        container.addSubview(toolbar)
        container.addSubview(canvas)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window.contentView = container
```

- [ ] **Step 3: 빌드 + 수동 검증**

Run: `swift test && Scripts/run.sh`
Expected:
1. 편집기 상단에 도구 세그먼트 + 색상 원 6개 + undo/redo + 복사/저장 버튼
2. 툴바에서 도구/색 변경 → 새 주석에 반영; 키보드 단축키(`a`/`r`/`o`/`t`/`b`/`n`)를 누르면 세그먼트 선택도 바뀜
3. 툴바 복사/저장 버튼이 `⌘C`/`⌘S`와 동일하게 동작

- [ ] **Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: 편집기 툴바 (도구 선택, 색상 팔레트, undo/redo, 복사/저장)"
```

---

### Task 16: 설정 창

**Files:**
- Create: `Sources/SnapScreenKit/Settings/SettingsView.swift`
- Create: `Sources/SnapScreenKit/Settings/SettingsWindowController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/StatusItemController.swift` (설정 열기 연결)
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`

- [ ] **Step 1: SettingsView 구현**

```swift
import SwiftUI
import KeyboardShortcuts

public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("단축키") {
                KeyboardShortcuts.Recorder("영역 캡처:", name: .captureArea)
                KeyboardShortcuts.Recorder("창 캡처:", name: .captureWindow)
                KeyboardShortcuts.Recorder("전체 화면 캡처:", name: .captureFullScreen)
            }
            Section("저장") {
                HStack {
                    Text("저장 폴더:")
                    Text(settings.saveFolderOverride ?? "시스템 스크린샷 위치 따름")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("변경…") { pickFolder() }
                    if settings.saveFolderOverride != nil {
                        Button("기본값") { settings.saveFolderOverride = nil }
                    }
                }
                TextField("파일명 접두어:", text: $settings.filenamePrefix)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveFolderOverride = url.path
        }
    }
}
```

- [ ] **Step 2: SettingsWindowController 구현**

```swift
import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public init(settings: SettingsStore) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen 설정"
        window.styleMask = [.titled, .closable]
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 3: 메뉴 연결**

`StatusItemController`의 init 시그니처에 `openSettings` 클로저 추가:

```swift
    private let openSettingsHandler: () -> Void

    public init(coordinator: CaptureCoordinator, openSettings: @escaping () -> Void) {
        self.openSettingsHandler = openSettings
        // ... 기존 코드 유지
    }

    @objc private func openSettings() { openSettingsHandler() }
```

`AppDelegate`에 설정 컨트롤러 추가:

```swift
    private var settingsController: SettingsWindowController?

    // applicationDidFinishLaunching에서 StatusItemController 생성 부분 교체:
        statusItemController = StatusItemController(coordinator: coordinator) { [weak self] in
            guard let self else { return }
            if self.settingsController == nil {
                self.settingsController = SettingsWindowController(settings: self.coordinator.settings)
            }
            self.settingsController?.show()
        }
```

- [ ] **Step 4: 빌드 + 수동 검증**

Run: `swift test && Scripts/run.sh`
Expected:
1. 메뉴바 → "설정…" → 설정 창 열림
2. 영역 캡처 단축키를 `⌘⇧9`로 변경 → 즉시 `⌘⇧9`로 영역 캡처 동작 (KeyboardShortcuts가 자동 재등록)
3. 저장 폴더 변경 → 다음 저장부터 해당 폴더에 저장; "기본값" → 시스템 위치로 복귀
4. 파일명 접두어 변경 → 저장 파일명에 반영
5. 앱 재시작 → 설정 유지

- [ ] **Step 5: Commit**

```bash
git add Sources/
git commit -m "feat: 설정 창 (단축키 변경, 저장 폴더, 파일명 접두어)"
```

---

### Task 17: 릴리스 준비 — 문서, 라이선스, CI

**Files:**
- Create: `LICENSE` (MIT)
- Create: `README.md` (기존 빈 파일 교체)
- Create: `docs/manual-test-checklist.md`
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: LICENSE 작성**

MIT 라이선스 전문, 저작권자 `snapscreen contributors`, 연도 2026.

- [ ] **Step 2: README.md 작성**

포함 내용 (한국어 + 영어 요약):
- 한 줄 소개, 기능 목록 (영역/창/전체 캡처, 주석 5종, 시스템 저장 위치 연동)
- 요구 사항: macOS 14+
- 설치: GitHub Releases에서 zip 다운로드 → `xattr -cr SnapScreen.app` 안내 (미서명 배포)
- 기본 단축키 표 (`⌘⇧1`/`⌘⇧2`/`⌘⇧0`)
- 빌드 방법: `Scripts/run.sh`
- 화면 기록 권한 안내
- 라이선스: MIT

- [ ] **Step 3: 수동 테스트 체크리스트 작성** — `docs/manual-test-checklist.md`

Task 9~16의 "수동 검증" 항목을 릴리스 전 체크리스트로 통합 정리한다. 섹션: 권한 플로우 / 전체·영역·창 캡처 / 멀티 모니터 / Retina / 편집기 도구 6종 / undo·redo / 내보내기(클립보드·파일) / 설정 유지. 각 항목은 `- [ ]` 체크박스.

- [ ] **Step 4: CI 워크플로 작성** — `.github/workflows/ci.yml`

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: swift test
      - run: Scripts/bundle.sh release
```

- [ ] **Step 5: 릴리스 워크플로 작성** — `.github/workflows/release.yml`

```yaml
name: Release
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  release:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: Scripts/bundle.sh release
      - run: /usr/bin/ditto -c -k --keepParent build/SnapScreen.app "SnapScreen-${GITHUB_REF_NAME}.zip"
      - run: gh release create "$GITHUB_REF_NAME" "SnapScreen-${GITHUB_REF_NAME}.zip" --generate-notes
        env:
          GH_TOKEN: ${{ github.token }}
```

- [ ] **Step 6: 인코딩 확인 + Commit**

```bash
file -I README.md docs/manual-test-checklist.md   # charset=utf-8 확인
git add LICENSE README.md docs/ .github/
git commit -m "chore: README, MIT 라이선스, 수동 테스트 체크리스트, CI/릴리스 워크플로"
```

- [ ] **Step 7: PR 생성**

`docs/manual-test-checklist.md`를 처음부터 끝까지 실기기에서 1회 완주한 후:

```bash
git push -u origin feature/mvp
gh pr create --title "feat: SnapScreen MVP (캡처 + 주석 편집기)" --body "$(cat <<'EOF'
## Summary
- macOS 14+ 메뉴바 상주 스크린샷 앱 MVP
- 전체/창/영역 캡처 (ScreenCaptureKit), 전역 단축키 ⌘⇧1/⌘⇧2/⌘⇧0
- 주석 편집기: 화살표·사각형·원·텍스트·픽셀레이트·스텝 배지, undo/redo
- 클립보드 복사 + 파일 저장 (시스템 스크린샷 저장 위치 연동)
- 설정 창 (단축키/저장 폴더/파일명), CI + 릴리스 워크플로

## Test plan
- [ ] `swift test` 전체 통과
- [ ] docs/manual-test-checklist.md 완주
EOF
)"
```

---

## 실행 순서 요약과 의존성

- Task 1~6은 순수 로직 + 스캐폴드: 순서대로 진행하되 3~6은 상호 독립
- Task 7~11이 캡처 파이프라인: 7(엔진) → 8(앱 셸) → 9(첫 E2E) → 10(영역) → 11(창)
- Task 12~15가 편집기: 12(뼈대) → 13(렌더러) → 14(인터랙션) → 15(툴바)
- Task 16(설정), 17(릴리스 준비)는 마지막
- **수동 검증이 있는 태스크(8~16)는 반드시 실기기에서 확인 후 커밋** — 화면 캡처/TCC/오버레이는 자동 테스트가 불가능하다
