# 홈 창 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 앱 실행 시 캡처 버튼 3개를 담은 홈 창을 띄우고, 창 유무에 따라 독 아이콘을 토글(.regular↔.accessory)한다 (v0.4.0)

**Architecture:** SwiftUI `HomeView`(캡처 버튼 3개 + 버전)를 `HomeWindowController`(NSWindowController)로 띄운다. `ActivationPolicyManager`가 등록된 표시 창 수를 추적해 0이면 `.accessory`(독 숨김)·1개 이상이면 `.regular`(독 표시)로 전환. 홈·편집기·설정 창이 모두 이 관리자에 register/unregister.

**Tech Stack:** Swift, AppKit(NSWindowController, NSApplication.ActivationPolicy), SwiftUI(NSHostingController), 기존 SnapScreenKit

**전제:**
- 브랜치 `feature/home-window`에서 작업 (설계 문서 커밋 있음). main 커밋 금지
- 커밋 메시지 끝에 빈 줄 후 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 컨벤션: UI 클래스 `@MainActor`, 창은 `isReleasedWhenClosed = false`, 로직 계층 AppKit 최소 의존으로 단위 테스트, 한글 파일 `file -I` UTF-8 확인
- 기존 시그니처: `CaptureCoordinator.beginCapture(_ mode: CaptureMode)` (public @MainActor), `CaptureMode { area, window, fullScreen }`, `EditorWindowController.init(result:settings:onClose:)`, `SettingsWindowController.init(settings:updateState:)`, `StatusItemController.init(coordinator:updateState:openSettings:)`, `AppInfo.version`

---

## 파일 구조 (완성 시점)

```
Sources/SnapScreenKit/
├── AppCore/ActivationPolicyManager.swift   # 창 집합 → 활성화 정책 (신규)
├── Home/HomeView.swift                     # SwiftUI 홈 뷰 (신규)
├── Home/HomeWindowController.swift          # 홈 창 컨트롤러 (신규)
├── AppCore/AppDelegate.swift               # 홈 창 시작 표시 + policyManager 배선 (수정)
├── AppCore/CaptureCoordinator.swift        # policyManager 주입, 편집기 등록 (수정)
├── AppCore/StatusItemController.swift      # "SnapScreen 홈…" 메뉴 항목 (수정)
├── Editor/EditorWindowController.swift     # policyManager register/unregister (수정)
├── Settings/SettingsWindowController.swift # policyManager register/unregister (수정)
├── Support/AppInfo.swift                   # 0.4.0 (수정)
└── Resources/Info.plist                    # 0.4.0, CFBundleVersion 5 (수정)
Tests/SnapScreenKitTests/ActivationPolicyManagerTests.swift
```

---

### Task 1: ActivationPolicyManager (TDD)

**Files:**
- Create: `Sources/SnapScreenKit/AppCore/ActivationPolicyManager.swift`
- Test: `Tests/SnapScreenKitTests/ActivationPolicyManagerTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
import AppKit
@testable import SnapScreenKit

@MainActor
final class ActivationPolicyManagerTests: XCTestCase {
    private final class Dummy {}

    func testPolicyForWindowCount() {
        XCTAssertEqual(ActivationPolicyManager.policy(forWindowCount: 0), .accessory)
        XCTAssertEqual(ActivationPolicyManager.policy(forWindowCount: 1), .regular)
        XCTAssertEqual(ActivationPolicyManager.policy(forWindowCount: 5), .regular)
    }

    func testRegisterUnregisterDrivesPolicy() {
        var applied: [NSApplication.ActivationPolicy] = []
        let mgr = ActivationPolicyManager(applyPolicy: { applied.append($0) })
        let a = ObjectIdentifier(Dummy())
        let b = ObjectIdentifier(Dummy())

        mgr.register(a)                       // 0→1: regular
        mgr.register(b)                       // 1→2: regular
        mgr.unregister(a)                     // 2→1: regular
        mgr.unregister(b)                     // 1→0: accessory
        XCTAssertEqual(applied, [.regular, .regular, .regular, .accessory])
        XCTAssertEqual(mgr.count, 0)
    }

    func testDuplicateRegisterIgnored() {
        var applied: [NSApplication.ActivationPolicy] = []
        let mgr = ActivationPolicyManager(applyPolicy: { applied.append($0) })
        let a = ObjectIdentifier(Dummy())
        mgr.register(a)
        mgr.register(a)                       // 중복 — 집합 크기 그대로
        XCTAssertEqual(mgr.count, 1)
        mgr.unregister(a)
        mgr.unregister(a)                     // 없는 것 해제 — 안전
        XCTAssertEqual(mgr.count, 0)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter ActivationPolicyManagerTests`
Expected: 컴파일 에러 — `cannot find 'ActivationPolicyManager'`

- [ ] **Step 3: 구현** — `ActivationPolicyManager.swift`

```swift
import AppKit

/// 표시 중인 앱 창 수에 따라 독 아이콘을 토글한다.
/// 등록 창이 0이면 .accessory(독 숨김·메뉴바 상주), 1개 이상이면 .regular(독 표시·포커스 정상).
@MainActor
public final class ActivationPolicyManager {
    private var registered: Set<ObjectIdentifier> = []
    private let applyPolicy: (NSApplication.ActivationPolicy) -> Void

    public init(applyPolicy: @escaping (NSApplication.ActivationPolicy) -> Void
                = { NSApp.setActivationPolicy($0) }) {
        self.applyPolicy = applyPolicy
    }

    /// 등록 창 수 → 정책 (순수 함수 — 단위 테스트 대상)
    public static func policy(forWindowCount count: Int) -> NSApplication.ActivationPolicy {
        count > 0 ? .regular : .accessory
    }

    public var count: Int { registered.count }

    public func register(_ token: ObjectIdentifier) {
        registered.insert(token)
        applyPolicy(Self.policy(forWindowCount: registered.count))
    }

    public func unregister(_ token: ObjectIdentifier) {
        registered.remove(token)
        applyPolicy(Self.policy(forWindowCount: registered.count))
    }

    // 편의: NSWindow ↔ 토큰
    public func register(_ window: NSWindow) { register(ObjectIdentifier(window)) }
    public func unregister(_ window: NSWindow) { unregister(ObjectIdentifier(window)) }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test`
Expected: 전부 PASS (기존 40 + 신규 3 = 43개)

- [ ] **Step 5: Commit**

```bash
git add Sources/SnapScreenKit/AppCore/ActivationPolicyManager.swift Tests/
git commit -m "feat: 활성화 정책 관리자 (창 수 → 독 표시/숨김 토글)"
```

---

### Task 2: HomeView (SwiftUI)

**Files:**
- Create: `Sources/SnapScreenKit/Home/HomeView.swift`

- [ ] **Step 1: 구현** — `HomeView.swift` (`Home/` 디렉토리 신규)

```swift
import SwiftUI

/// 홈 창 내용: 캡처 버튼 3개(단축키 병기) + 하단 버전.
/// 버튼은 주입된 onCapture 클로저로 CaptureCoordinator.beginCapture를 호출한다.
public struct HomeView: View {
    let onCapture: (CaptureMode) -> Void

    public init(onCapture: @escaping (CaptureMode) -> Void) {
        self.onCapture = onCapture
    }

    private struct Item {
        let mode: CaptureMode
        let symbol: String
        let title: String
        let shortcut: String
    }

    private let items: [Item] = [
        Item(mode: .area, symbol: "rectangle.dashed", title: "영역", shortcut: "⌘⇧1"),
        Item(mode: .window, symbol: "macwindow", title: "창", shortcut: "⌘⇧2"),
        Item(mode: .fullScreen, symbol: "display", title: "전체 화면", shortcut: "⌘⇧0")
    ]

    public var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 12) {
                ForEach(items, id: \.symbol) { item in
                    Button {
                        onCapture(item.mode)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: item.symbol).font(.system(size: 28))
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.shortcut)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
                }
            }
            HStack {
                Spacer()
                Text("v\(AppInfo.version)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(22)
        .frame(width: 420)
    }
}
```

- [ ] **Step 2: 빌드 확인**

Run: `swift build && swift test`
Expected: 빌드 성공, 43개 PASS (HomeView는 아직 미사용이라 경고 없이 컴파일만)

- [ ] **Step 3: Commit**

```bash
git add Sources/SnapScreenKit/Home/
git commit -m "feat: 홈 뷰 (캡처 버튼 3개 + 버전)"
```

---

### Task 3: HomeWindowController

**Files:**
- Create: `Sources/SnapScreenKit/Home/HomeWindowController.swift`

- [ ] **Step 1: 구현** — `HomeWindowController.swift`

```swift
import AppKit
import SwiftUI

/// 홈 창. 표시 시 ActivationPolicyManager에 등록(독 표시), 닫힐 때 해제(창 0개면 독 숨김).
@MainActor
public final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private let policyManager: ActivationPolicyManager

    public init(policyManager: ActivationPolicyManager,
                onCapture: @escaping (CaptureMode) -> Void) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: HomeView(onCapture: onCapture))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen"
        window.styleMask = [.titled, .closable, .miniaturizable] // 리사이즈 불가
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        guard let window else { return }
        policyManager.register(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        policyManager.unregister(window)
    }
}
```

- [ ] **Step 2: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: 빌드 성공, 43개 PASS

- [ ] **Step 3: Commit**

```bash
git add Sources/SnapScreenKit/Home/
git commit -m "feat: 홈 창 컨트롤러 (표시/닫힘 시 정책 등록/해제)"
```

---

### Task 4: 편집기·설정 창을 정책 관리자에 등록

**Files:**
- Modify: `Sources/SnapScreenKit/Editor/EditorWindowController.swift`
- Modify: `Sources/SnapScreenKit/Settings/SettingsWindowController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift`

- [ ] **Step 1: EditorWindowController에 policyManager 주입**

`EditorWindowController`의 프로퍼티와 init 시그니처를 변경한다. 프로퍼티 추가:

```swift
    private let policyManager: ActivationPolicyManager?
```

init 시그니처를 다음으로 교체 (기존 `init(result:settings:onClose:)`):

```swift
    public init(result: CaptureResult, settings: SettingsStore,
                policyManager: ActivationPolicyManager? = nil,
                onClose: (() -> Void)? = nil) {
        self.result = result
        self.settings = settings
        self.policyManager = policyManager
        self.onClose = onClose
```

`super.init(window: window)` 다음 줄들(기존 `window.delegate = self` 근처)이 이미 delegate를 설정한다. init 마지막의 `window.makeKeyAndOrderFront(nil)` 또는 `NSApp.activate` 근처에 등록 추가 — init 본문에서 window를 표시하는 코드 뒤에:

```swift
        policyManager?.register(window)
```

`windowWillClose`에 해제 추가 (기존 `onClose?()` 호출부와 같은 메서드):

```swift
    public func windowWillClose(_ notification: Notification) {
        if let window { policyManager?.unregister(window) }
        onClose?()
        onClose = nil
    }
```

(기존 windowWillClose가 이미 있으면 첫 줄만 추가. 없으면 위 메서드 전체 추가 — EditorWindowController는 NSWindowDelegate를 이미 채택하고 있다.)

- [ ] **Step 2: SettingsWindowController에 policyManager 주입**

`SettingsWindowController`를 `NSWindowDelegate` 채택으로 바꾸고 정책 등록을 추가한다. 전체를 다음으로 교체:

```swift
import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let policyManager: ActivationPolicyManager?

    public init(settings: SettingsStore, updateState: UpdateState,
                policyManager: ActivationPolicyManager? = nil) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: SettingsView(settings: settings,
                                                                 updateState: updateState))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        guard let window else { return }
        policyManager?.register(window)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        if let window { policyManager?.unregister(window) }
    }
}
```

- [ ] **Step 3: CaptureCoordinator가 policyManager를 보유하고 편집기에 전달**

`CaptureCoordinator`에 프로퍼티 추가:

```swift
    public var policyManager: ActivationPolicyManager?
```

`handleCaptured`의 EditorWindowController 생성을 다음으로 교체:

```swift
    func handleCaptured(_ result: CaptureResult) {
        // controller가 onClose 클로저를 통해 자신을 보유하는 순환은
        // windowWillClose에서 onClose = nil로 끊긴다
        var controller: EditorWindowController?
        controller = EditorWindowController(result: result, settings: settings,
                                            policyManager: policyManager) { [weak self] in
            self?.editors.removeAll { $0 === controller }
        }
        if let controller { editors.append(controller) }
    }
```

- [ ] **Step 4: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: 빌드 성공 (경고 0), 43개 PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/
git commit -m "feat: 편집기·설정 창을 활성화 정책 관리자에 등록"
```

---

### Task 5: AppDelegate 배선 + 메뉴 "SnapScreen 홈…"

**Files:**
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`
- Modify: `Sources/SnapScreenKit/AppCore/StatusItemController.swift`

- [ ] **Step 1: AppDelegate에 정책 관리자 + 홈 창 배선**

`AppDelegate`에 프로퍼티 추가:

```swift
    private let activationPolicyManager = ActivationPolicyManager()
    private var homeWindowController: HomeWindowController?
```

`applicationDidFinishLaunching`에서 **기존 `NSApp.setActivationPolicy(.accessory)` 줄을 제거**한다 (정책은 이제 ActivationPolicyManager가 창 등록에 따라 관리). 그리고 `coordinator = CaptureCoordinator()` 다음에 policyManager 연결 + 홈 창 생성/표시를 추가:

```swift
        coordinator = CaptureCoordinator()
        coordinator.policyManager = activationPolicyManager

        homeWindowController = HomeWindowController(
            policyManager: activationPolicyManager,
            onCapture: { [weak coordinator] mode in coordinator?.beginCapture(mode) })
        homeWindowController?.show()
```

`StatusItemController` 생성부의 설정 열기 클로저에서 `SettingsWindowController` 생성에 policyManager를 전달하고, 새로 "홈 열기" 클로저도 넘긴다 (다음 Step에서 시그니처 확장). 설정 컨트롤러 생성 라인 교체:

```swift
                self.settingsController = SettingsWindowController(
                    settings: self.coordinator.settings,
                    updateState: self.updateState,
                    policyManager: self.activationPolicyManager)
```

`StatusItemController(...)` 호출을 홈 열기 클로저 포함으로 교체:

```swift
        statusItemController = StatusItemController(
            coordinator: coordinator,
            updateState: updateState,
            openHome: { [weak self] in self?.homeWindowController?.show() },
            openSettings: { [weak self] in
                guard let self else { return }
                if self.settingsController == nil {
                    self.settingsController = SettingsWindowController(
                        settings: self.coordinator.settings,
                        updateState: self.updateState,
                        policyManager: self.activationPolicyManager)
                }
                self.settingsController?.show()
            })
```

(참고: `applicationShouldTerminateAfterLastWindowClosed`는 구현하지 않는다 — 미구현 시 기본값 false라 창을 다 닫아도 앱이 종료되지 않는다. accessory↔regular를 오가도 이 기본 동작은 유지된다.)

- [ ] **Step 2: StatusItemController에 "홈" 메뉴 항목 + openHome 클로저**

`StatusItemController`의 프로퍼티/init에 `openHome`을 추가하고 메뉴 항목을 넣는다. 프로퍼티 추가:

```swift
    private let openHomeHandler: () -> Void
```

init 시그니처를 다음으로 교체:

```swift
    public init(coordinator: CaptureCoordinator, updateState: UpdateState,
                openHome: @escaping () -> Void,
                openSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.updateState = updateState
        self.openHomeHandler = openHome
        self.openSettingsHandler = openSettings
```

메뉴 구성에서 캡처 항목들 위에 "홈" 항목 + 구분선을 추가한다. 기존 `menu.addItem(item("영역 캡처", ...))` 앞에:

```swift
        menu.addItem(item("SnapScreen 홈…", #selector(StatusItemController.openHome)))
        menu.addItem(.separator())
        menu.addItem(item("영역 캡처", #selector(captureArea)))
```

`@objc` 액션 추가 (기존 `openSettings` 옆):

```swift
    @objc private func openHome() { openHomeHandler() }
```

- [ ] **Step 3: 빌드 + 테스트 + 상주 확인**

Run: `swift test && Scripts/run.sh` → `pgrep -x SnapScreen` → `pkill -x SnapScreen`
Expected: 43개 PASS, 앱 상주. 육안 확인 항목 보고: 실행 시 홈 창 + 독 아이콘 표시 / 캡처 버튼 3종 동작 / 홈 창 닫으면 독 사라지고 메뉴바 유지 / 편집기 여러 개일 때 독 유지, 다 닫으면 사라짐 / 메뉴 "SnapScreen 홈…"으로 재열기 / 모든 창 닫아도 앱 상주

- [ ] **Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: 앱 시작 시 홈 창 표시 + 메뉴 홈 항목 + 정책 관리자 배선"
```

---

### Task 6: 문서 + v0.4.0 범프 + PR

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `Sources/SnapScreenKit/Support/AppInfo.swift`
- Modify: `Resources/Info.plist`

- [ ] **Step 1: 체크리스트에 "12. 홈 창" 섹션 추가** — `docs/manual-test-checklist.md` 끝에:

```markdown
## 12. 홈 창

- [ ] 앱 실행 시 홈 창이 자동으로 뜨고 독 아이콘이 나타난다
- [ ] 홈 창의 캡처 버튼 3종(영역/창/전체)이 각각 정상 동작한다 (기존 캡처 흐름 시작)
- [ ] 홈 창을 닫으면 독 아이콘이 사라지고 메뉴바 상주만 유지된다
- [ ] 편집기 창이 여러 개 떠 있을 때 홈 창을 닫아도 독 아이콘이 유지된다 (창이 남아 있으므로)
- [ ] 모든 창(홈+편집기+설정)을 닫으면 독 아이콘이 사라진다
- [ ] 메뉴바 "SnapScreen 홈…"으로 닫은 홈 창을 다시 열 수 있다
- [ ] 모든 창을 닫아도 앱이 종료되지 않고 메뉴바에 상주한다
- [ ] 홈 창 표시 중 ⌘Tab에 SnapScreen이 노출된다 (.regular 정책)
```

- [ ] **Step 2: README 갱신** — 기능 목록/실행 설명에 홈 창 언급 추가 (실제 파일 읽고 맞는 위치에). 예: "실행하면 캡처 버튼이 있는 홈 창이 열리고, 창을 닫으면 메뉴바에 상주합니다."

- [ ] **Step 3: CLAUDE.md 갱신** — 아키텍처 모듈 목록에 Home 모듈과 활성화 정책을 추가. `- **Updater/**` 줄 다음이나 적절한 위치에:

```markdown
- **Home/** — 홈 창(`HomeView` 캡처 버튼 3개 + `HomeWindowController`). 실행 시 자동 표시.
```

그리고 AppCore 설명에 활성화 정책 한 줄 추가 (기존 AppDelegate 항목 근처):

```markdown
- **활성화 정책**: `ActivationPolicyManager`가 등록된 표시 창 수를 추적 — 0이면 `.accessory`(독 숨김), 1개 이상이면 `.regular`(독 표시). 홈·편집기·설정 창이 생성/닫힘 시 register/unregister. `AppDelegate`는 더 이상 시작 시 `.accessory`를 직접 설정하지 않는다.
```

- [ ] **Step 4: 버전 범프**

- `AppInfo.swift`: `version = "0.4.0"`
- `Resources/Info.plist`: `CFBundleShortVersionString` → `0.4.0`, `CFBundleVersion` → `5`

- [ ] **Step 5: 최종 검증**

```bash
swift test                        # 43개 PASS
Scripts/bundle.sh release         # OK
file -I README.md docs/manual-test-checklist.md CLAUDE.md   # utf-8
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist  # 0.4.0
```

- [ ] **Step 6: Commit + Push + PR**

```bash
git add docs/ README.md CLAUDE.md Sources/ Resources/
git commit -m "chore: 홈 창 문서 + v0.4.0 버전 범프"
git push -u origin feature/home-window
gh pr create --title "feat: 홈 창 (실행 시 캡처 런처 + 독 아이콘 토글)" --body "$(cat <<'EOF'
## Summary
- 앱 실행 시 캡처 버튼 3개(영역/창/전체, 단축키 병기)를 담은 홈 창 자동 표시
- 홈 창을 열면 독 아이콘 등장(+⌘Tab 노출), 창을 닫으면 사라지고 메뉴바 상주만 유지
- `ActivationPolicyManager`가 표시 창 수를 추적해 `.regular`(≥1)/`.accessory`(0) 토글 — 홈·편집기·설정 창이 모두 등록되어, 편집기가 여러 개일 때 홈만 닫아도 독 유지
- 메뉴바에 "SnapScreen 홈…" 항목 추가 (닫은 홈 창 재열기)
- 설정 접근은 기존 메뉴바 "설정…" 유지, v0.4.0 범프

## 설계/계획
- Spec: `docs/superpowers/specs/2026-07-06-home-window-design.md`
- Plan: `docs/superpowers/plans/2026-07-06-home-window.md`

## Test plan
- [ ] `swift test` 43개 통과 (ActivationPolicyManager 단위 테스트 3개 포함)
- [ ] 수동: 실행 시 홈 창+독 표시, 캡처 버튼, 창 닫으면 독 사라짐, 편집기 다중 시 정책 유지, 메뉴 홈 재열기 (checklist §12)
EOF
)"
```

---

## 실행 순서와 검증 한계

- Task 1(정책 관리자) → 2(HomeView) → 3(HomeWindowController) → 4(편집기·설정 등록) → 5(AppDelegate+메뉴) → 6(문서·범프·PR). 순차 의존.
- 활성화 정책의 실제 독 토글·포커스·⌘Tab 동작은 자동 테스트 불가(GUI) — Task 5의 수동 검증 + 체크리스트 §12로 확인. 단위 테스트는 `ActivationPolicyManager`의 창 수→정책 매핑만 커버.
- 릴리스(`make release VERSION=v0.4.0`)는 PR 머지 후 별도.
