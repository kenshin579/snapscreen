# 인앱 업데이트 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 설정 창에 버전 표시 + GitHub Releases 최신 버전 확인 + 업그레이드 클릭 한 번으로 다운로드→교체→재실행

**Architecture:** 새 모듈 `Sources/SnapScreenKit/Updater/` 3파일 — `UpdateChecker`(AppKit 비의존, GitHub API 조회+시맨틱 버전 비교, 단위 테스트 대상), `UpdateState`(@MainActor ObservableObject, 설정 창·메뉴바 공유 상태), `UpdateInstaller`(다운로드→ditto 해제→검증→번들 교체→재실행). AppDelegate가 시작 시 quiet 자동 확인.

**Tech Stack:** Swift 5.9+, URLSession(async), Combine(@Published 구독), `/usr/bin/ditto`, GitHub REST API (비인증)

**전제:**
- 브랜치 `feature/in-app-update`에서 작업 (이미 체크아웃됨 — 설계 문서 커밋 포함). main 커밋 금지
- 커밋 메시지 끝에 빈 줄 후 `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`
- 기존 컨벤션 준수: UI 클래스 `@MainActor`, 창은 `isReleasedWhenClosed = false`, 하드 실패는 `Notifier.alertFailure`, 로직 계층 AppKit 비의존, 한글 파일 `file -I`로 UTF-8 확인
- 캡처 관련 실행 확인은 `Scripts/run.sh` (CLAUDE.md 참고)

---

## 파일 구조 (완성 시점)

```
Sources/SnapScreenKit/Updater/
├── UpdateChecker.swift    # GitHub API 조회, 버전 비교, zip 에셋 선택 (AppKit 비의존)
├── UpdateState.swift      # @MainActor ObservableObject 공유 상태
└── UpdateInstaller.swift  # 다운로드/해제/검증/교체/재실행
Tests/SnapScreenKitTests/UpdateCheckerTests.swift
수정: AppDelegate.swift, StatusItemController.swift, SettingsView.swift,
      SettingsWindowController.swift, docs/manual-test-checklist.md, CLAUDE.md
```

---

### Task 1: UpdateChecker (TDD)

**Files:**
- Create: `Sources/SnapScreenKit/Updater/UpdateChecker.swift`
- Test: `Tests/SnapScreenKitTests/UpdateCheckerTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

```swift
import XCTest
@testable import SnapScreenKit

final class UpdateCheckerTests: XCTestCase {
    // MARK: 버전 비교

    func testCompareVersions() {
        XCTAssertEqual(UpdateChecker.compareVersions("0.1.0", "0.1.0"), 0)
        XCTAssertLessThan(UpdateChecker.compareVersions("0.1.0", "0.2.0"), 0)
        XCTAssertGreaterThan(UpdateChecker.compareVersions("1.0.0", "0.9.9"), 0)
        XCTAssertLessThan(UpdateChecker.compareVersions("0.2.0", "0.10.0"), 0)  // 숫자 비교 (문자열 비교 아님)
        XCTAssertEqual(UpdateChecker.compareVersions("1.0", "1.0.0"), 0)        // 자릿수 상이
        XCTAssertGreaterThan(UpdateChecker.compareVersions("1.0.1", "1.0"), 0)
    }

    // MARK: 릴리스 JSON 해석

    private func releaseJSON(tag: String, assetNames: [String]) -> Data {
        let assets = assetNames.map {
            #"{"name": "\#($0)", "browser_download_url": "https://github.com/kenshin579/snapscreen/releases/download/\#(tag)/\#($0)"}"#
        }.joined(separator: ",")
        return #"{"tag_name": "\#(tag)", "assets": [\#(assets)]}"#.data(using: .utf8)!
    }

    func testStatusAvailableWhenNewerVersion() {
        let json = releaseJSON(tag: "v0.2.0", assetNames: ["SnapScreen-v0.2.0.zip"])
        let status = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json)
        guard case .available(let version, let url) = status else {
            return XCTFail("expected .available, got \(status)")
        }
        XCTAssertEqual(version, "0.2.0")
        XCTAssertTrue(url.absoluteString.hasSuffix("SnapScreen-v0.2.0.zip"))
    }

    func testStatusUpToDateWhenSameVersion() {
        let json = releaseJSON(tag: "v0.1.0", assetNames: ["SnapScreen-v0.1.0.zip"])
        XCTAssertEqual(UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json), .upToDate)
    }

    func testStatusUpToDateWhenCurrentIsNewer() {
        // 개발 빌드가 릴리스보다 앞서는 경우 다운그레이드 제안 금지
        let json = releaseJSON(tag: "v0.1.0", assetNames: ["SnapScreen-v0.1.0.zip"])
        XCTAssertEqual(UpdateChecker.status(currentVersion: "0.9.0", releaseJSON: json), .upToDate)
    }

    func testStatusSelectsZipAsset() {
        let json = releaseJSON(tag: "v0.2.0",
                               assetNames: ["checksums.txt", "SnapScreen-v0.2.0.zip"])
        guard case .available(_, let url) = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json) else {
            return XCTFail("expected .available")
        }
        XCTAssertTrue(url.absoluteString.hasSuffix(".zip"))
    }

    func testStatusFailsWhenNoZipAsset() {
        let json = releaseJSON(tag: "v0.2.0", assetNames: ["checksums.txt"])
        guard case .failed = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json) else {
            return XCTFail("expected .failed")
        }
    }

    func testStatusFailsOnMalformedJSON() {
        let status = UpdateChecker.status(currentVersion: "0.1.0",
                                          releaseJSON: Data("not json".utf8))
        guard case .failed = status else { return XCTFail("expected .failed") }
    }

    func testTagWithoutVPrefix() {
        let json = releaseJSON(tag: "0.2.0", assetNames: ["SnapScreen-0.2.0.zip"])
        guard case .available(let version, _) = UpdateChecker.status(currentVersion: "0.1.0", releaseJSON: json) else {
            return XCTFail("expected .available")
        }
        XCTAssertEqual(version, "0.2.0")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter UpdateCheckerTests`
Expected: 컴파일 에러 — `cannot find 'UpdateChecker'`

- [ ] **Step 3: 구현** — `UpdateChecker.swift`

```swift
import Foundation

public enum UpdateStatus: Equatable {
    case upToDate
    case available(version: String, downloadURL: URL)
    case failed(String)
}

/// GitHub /releases/latest 응답의 필요한 부분만 디코딩
struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
    let tagName: String
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

public enum UpdateChecker {
    public static let latestReleaseURL =
        URL(string: "https://api.github.com/repos/kenshin579/snapscreen/releases/latest")!
    public static let releasesPageURL =
        URL(string: "https://github.com/kenshin579/snapscreen/releases")!

    /// 시맨틱 버전 비교. 반환: a<b 음수 / a==b 0 / a>b 양수. 자릿수가 달라도 동작 ("1.0" == "1.0.0")
    public static func compareVersions(_ a: String, _ b: String) -> Int {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    /// 릴리스 JSON을 해석해 업데이트 상태를 결정한다 (순수 함수 — 단위 테스트 대상)
    public static func status(currentVersion: String, releaseJSON: Data) -> UpdateStatus {
        let release: GitHubRelease
        do {
            release = try JSONDecoder().decode(GitHubRelease.self, from: releaseJSON)
        } catch {
            return .failed("릴리스 정보를 해석하지 못했습니다")
        }
        let latest = release.tagName.hasPrefix("v")
            ? String(release.tagName.dropFirst()) : release.tagName
        guard compareVersions(currentVersion, latest) < 0 else { return .upToDate }
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }) else {
            return .failed("릴리스에 zip 에셋이 없습니다")
        }
        return .available(version: latest, downloadURL: asset.browserDownloadURL)
    }

    /// GitHub API 호출 + 상태 결정
    public static func check(currentVersion: String = AppInfo.version) async -> UpdateStatus {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failed("업데이트 확인 실패 (HTTP)")
            }
            return status(currentVersion: currentVersion, releaseJSON: data)
        } catch {
            return .failed("업데이트 확인 실패 (네트워크)")
        }
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter UpdateCheckerTests`
Expected: PASS (8 tests). 이어서 `swift test` 전체 35개(기존 27 + 8) PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/SnapScreenKit/Updater/ Tests/
git commit -m "feat: 업데이트 확인기 (GitHub 릴리스 조회 + 시맨틱 버전 비교)"
```

---

### Task 2: UpdateState + AppDelegate 배선 (자동 확인 + 업데이트 후 안내)

**Files:**
- Create: `Sources/SnapScreenKit/Updater/UpdateState.swift`
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`

- [ ] **Step 1: UpdateState 구현**

```swift
import Foundation

@MainActor
public final class UpdateState: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, downloadURL: URL)
        case installing
        case failed(String)
    }

    @Published public var phase: Phase = .idle

    public init() {}

    /// quiet=true(시작 시 자동 확인): 실패해도 조용히 .idle로 되돌린다 (스펙 §7)
    public func check(quiet: Bool = false) async {
        guard phase != .checking, phase != .installing else { return }
        phase = .checking
        switch await UpdateChecker.check() {
        case .upToDate:
            phase = .upToDate
        case .available(let version, let downloadURL):
            phase = .available(version: version, downloadURL: downloadURL)
        case .failed(let message):
            phase = quiet ? .idle : .failed(message)
        }
    }
}
```

- [ ] **Step 2: AppDelegate 배선**

`AppDelegate`에 프로퍼티 추가:

```swift
    public private(set) var updateState = UpdateState()
```

`applicationDidFinishLaunching` 끝에 추가:

```swift
        // 시작 시 자동 업데이트 확인 (실패 시 조용히 무시)
        Task { await updateState.check(quiet: true) }

        // 업데이트 후 첫 실행이면 권한 재승인 안내 (ad-hoc 서명 제약)
        let lastRunKey = "lastRunVersion"
        let lastRun = UserDefaults.standard.string(forKey: lastRunKey)
        if let lastRun, lastRun != AppInfo.version {
            Notifier.show(title: "SnapScreen \(AppInfo.version)(으)로 업데이트됨",
                          body: "화면 기록 권한을 다시 켜야 할 수 있습니다.")
        }
        UserDefaults.standard.set(AppInfo.version, forKey: lastRunKey)
```

- [ ] **Step 3: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: 빌드 성공, 35개 PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: 업데이트 상태 모델 + 시작 시 자동 확인 + 업데이트 후 권한 안내"
```

---

### Task 3: UpdateInstaller

**Files:**
- Create: `Sources/SnapScreenKit/Updater/UpdateInstaller.swift`

- [ ] **Step 1: 구현**

```swift
import AppKit

/// 다운로드 → 압축 해제 → 검증 → 번들 교체 → 재실행.
/// 성공 시 NSApp.terminate로 돌아오지 않는다. 실패 시 에러 메시지를 반환한다.
@MainActor
public enum UpdateInstaller {
    public static func install(version: String, downloadURL: URL) async -> String? {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory
            .appendingPathComponent("SnapScreenUpdate-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)

            // 1. 다운로드
            let (downloaded, response) = try await URLSession.shared.download(from: downloadURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return "다운로드 실패 (HTTP)"
            }
            let zip = workDir.appendingPathComponent("update.zip")
            try fm.moveItem(at: downloaded, to: zip)

            // 2. 압축 해제 (릴리스 zip을 만든 ditto와 동일 도구)
            let unzipDir = workDir.appendingPathComponent("unzipped")
            try runProcess("/usr/bin/ditto", ["-x", "-k", zip.path, unzipDir.path])

            // 3. 검증: 번들 존재 + 버전 일치
            let newApp = unzipDir.appendingPathComponent("SnapScreen.app")
            let plistURL = newApp.appendingPathComponent("Contents/Info.plist")
            guard let plist = NSDictionary(contentsOf: plistURL),
                  plist["CFBundleShortVersionString"] as? String == version else {
                return "다운로드한 앱 검증에 실패했습니다"
            }

            // 4. 번들 교체 (실행 중 rename은 macOS에서 허용)
            let currentURL = Bundle.main.bundleURL
            let backupURL = workDir.appendingPathComponent("SnapScreen-old.app")
            try fm.moveItem(at: currentURL, to: backupURL)
            do {
                try fm.moveItem(at: newApp, to: currentURL)
            } catch {
                try? fm.moveItem(at: backupURL, to: currentURL) // 롤백
                return "앱 교체에 실패했습니다 (설치 폴더 권한 확인): \(error.localizedDescription)"
            }

            // 5. 재실행: 분리 프로세스가 1초 후 새 번들을 열고, 현재 앱은 종료
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"\(currentURL.path)\""]
            try relaunch.run()
            NSApp.terminate(nil)
            return nil // 도달하지 않음
        } catch {
            return "업데이트 실패: \(error.localizedDescription)"
        }
    }

    private static func runProcess(_ path: String, _ args: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "UpdateInstaller", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey:
                                        "\(path) 종료 코드 \(process.terminationStatus)"])
        }
    }
}
```

- [ ] **Step 2: 빌드 + 테스트**

Run: `swift build && swift test`
Expected: 빌드 성공 (경고 0), 35개 PASS. 설치 로직의 실검증은 v0.2.0 릴리스 후 E2E (체크리스트 — Task 6).

- [ ] **Step 3: Commit**

```bash
git add Sources/
git commit -m "feat: 업데이트 설치기 (다운로드→검증→번들 교체→재실행)"
```

---

### Task 4: 설정 창 "정보" 섹션

**Files:**
- Modify: `Sources/SnapScreenKit/Settings/SettingsView.swift`
- Modify: `Sources/SnapScreenKit/Settings/SettingsWindowController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift` (updateState 전달)

- [ ] **Step 1: SettingsView에 updateState 주입 + "정보" 섹션 추가**

`SettingsView` 프로퍼티/init 변경:

```swift
public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateState: UpdateState

    public init(settings: SettingsStore, updateState: UpdateState) {
        self.settings = settings
        self.updateState = updateState
    }
```

`Form` 맨 아래(기존 "저장" Section 다음)에 추가:

```swift
            Section("정보") {
                LabeledContent("버전", value: AppInfo.version)
                HStack {
                    updateStatusText
                    Spacer()
                    Button("업데이트 확인") {
                        Task { await updateState.check() }
                    }
                    .disabled(updateState.phase == .checking || updateState.phase == .installing)
                    if case .available(let version, let downloadURL) = updateState.phase {
                        Button("업그레이드") {
                            upgrade(version: version, downloadURL: downloadURL)
                        }
                    } else if updateState.phase == .installing {
                        Button("다운로드 중…") {}.disabled(true)
                    }
                }
            }
```

body 아래에 보조 뷰/메서드 추가:

```swift
    @ViewBuilder
    private var updateStatusText: some View {
        switch updateState.phase {
        case .idle:
            Text("최신 버전: 미확인").foregroundStyle(.secondary)
        case .checking:
            Text("확인 중…").foregroundStyle(.secondary)
        case .upToDate:
            Text("최신 버전입니다 ✓").foregroundStyle(.secondary)
        case .available(let version, _):
            Text("v\(version) 사용 가능").fontWeight(.medium)
        case .installing:
            Text("설치 중…").foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    private func upgrade(version: String, downloadURL: URL) {
        updateState.phase = .installing
        Task {
            if let errorMessage = await UpdateInstaller.install(version: version,
                                                                downloadURL: downloadURL) {
                updateState.phase = .failed(errorMessage)
                let alert = NSAlert()
                alert.messageText = "업데이트 실패"
                alert.informativeText = errorMessage + "\n릴리스 페이지에서 수동으로 설치할 수 있습니다."
                alert.addButton(withTitle: "릴리스 페이지 열기")
                alert.addButton(withTitle: "닫기")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
                }
            }
            // 성공 시 앱이 종료·재실행되므로 후속 코드 없음
        }
    }
```

- [ ] **Step 2: SettingsWindowController와 AppDelegate 시그니처 전파**

`SettingsWindowController.init`:

```swift
    public init(settings: SettingsStore, updateState: UpdateState) {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings,
                                                                 updateState: updateState))
        // ... 나머지 기존 코드 유지
```

`AppDelegate`의 설정 컨트롤러 생성부 갱신:

```swift
                self.settingsController = SettingsWindowController(
                    settings: self.coordinator.settings,
                    updateState: self.updateState)
```

- [ ] **Step 3: 빌드 + 테스트 + 상주 확인**

Run: `swift test && Scripts/run.sh` → `pgrep -x SnapScreen` 확인 → `pkill -x SnapScreen`
Expected: 35개 PASS, 앱 상주. 육안 확인 항목은 보고서에 명시 (설정 창 "정보" 섹션 표시, 확인 버튼 동작 — 현재 v0.1.0이 최신이므로 "최신 버전입니다 ✓" 표시가 정상)

- [ ] **Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: 설정 창 정보 섹션 (버전 표시 + 업데이트 확인/업그레이드)"
```

---

### Task 5: 메뉴바 "업데이트 가능" 항목

**Files:**
- Modify: `Sources/SnapScreenKit/AppCore/StatusItemController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift` (updateState 전달)

- [ ] **Step 1: StatusItemController가 UpdateState를 구독**

`import Combine` 추가. 프로퍼티/init 변경:

```swift
    private let updateState: UpdateState
    private var updateMenuItem: NSMenuItem?
    private var updateSeparator: NSMenuItem?
    private var phaseCancellable: AnyCancellable?

    public init(coordinator: CaptureCoordinator, updateState: UpdateState,
                openSettings: @escaping () -> Void) {
        self.updateState = updateState
        self.openSettingsHandler = openSettings
        // ... 기존 메뉴 구성 코드 유지 ...

        phaseCancellable = updateState.$phase.sink { [weak self] phase in
            self?.refreshUpdateItem(for: phase)
        }
    }
```

메서드 추가 (기존 `item(_:_:)` 헬퍼 아래):

```swift
    /// .available일 때만 메뉴 최상단에 "업데이트 가능 (vX.Y.Z)…" + 구분선을 노출한다
    private func refreshUpdateItem(for phase: UpdateState.Phase) {
        guard let menu = statusItem.menu else { return }
        if let item = updateMenuItem { menu.removeItem(item); updateMenuItem = nil }
        if let sep = updateSeparator { menu.removeItem(sep); updateSeparator = nil }

        guard case .available(let version, _) = phase else { return }
        let item = NSMenuItem(title: "업데이트 가능 (v\(version))…",
                              action: #selector(StatusItemController.openSettings),
                              keyEquivalent: "")
        item.target = self
        let separator = NSMenuItem.separator()
        menu.insertItem(item, at: 0)
        menu.insertItem(separator, at: 1)
        updateMenuItem = item
        updateSeparator = separator
    }
```

- [ ] **Step 2: AppDelegate 호출부 갱신**

```swift
        statusItemController = StatusItemController(
            coordinator: coordinator,
            updateState: updateState) { [weak self] in
            // ... 기존 설정 열기 클로저 유지
        }
```

- [ ] **Step 3: 빌드 + 테스트 + 상주 확인**

Run: `swift test && Scripts/run.sh` → `pgrep` → `pkill -x SnapScreen`
Expected: 35개 PASS. 육안 확인: 현재는 최신 버전이라 메뉴에 업데이트 항목이 **없어야** 정상 (E2E는 v0.2.0 릴리스 후)

- [ ] **Step 4: Commit**

```bash
git add Sources/
git commit -m "feat: 메뉴바 업데이트 가능 항목 (UpdateState 구독)"
```

---

### Task 6: 체크리스트 + CLAUDE.md 갱신 + 버전 범프

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `CLAUDE.md`
- Modify: `Sources/SnapScreenKit/Support/AppInfo.swift` (0.1.0 → 0.2.0)
- Modify: `Resources/Info.plist` (0.1.0 → 0.2.0, CFBundleVersion 1 → 2)

- [ ] **Step 1: 체크리스트에 "11. 업데이트" 섹션 추가**

`docs/manual-test-checklist.md` 끝에:

```markdown
## 11. 업데이트

- [ ] 설정 창 "정보" 섹션에 현재 버전이 표시된다
- [ ] "업데이트 확인" 클릭 시 최신 버전이면 "최신 버전입니다 ✓"가 표시된다
- [ ] 네트워크를 끊고 "업데이트 확인" 클릭 시 실패 메시지가 표시된다
- [ ] (구버전 설치 상태에서) 시작 시 자동 확인으로 메뉴바에 "업데이트 가능 (vX.Y.Z)…" 항목이 나타난다
- [ ] 메뉴바 업데이트 항목 클릭 시 설정 창이 열린다
- [ ] "업그레이드" 클릭 → 다운로드 → 앱이 재실행되고 새 버전으로 실행된다
- [ ] 업데이트 후 첫 실행에 "화면 기록 권한을 다시 켜야 할 수 있습니다" 알림이 표시된다
- [ ] 업데이트 후 화면 기록 권한을 다시 켜면 캡처가 정상 동작한다
```

- [ ] **Step 2: CLAUDE.md 아키텍처 모듈 목록에 Updater 추가**

`- **Settings/**, **Support/**` 줄 앞에 추가:

```markdown
- **Updater/** — 인앱 업데이트. `UpdateChecker`(GitHub API+버전 비교, AppKit 비의존), `UpdateState`(공유 상태), `UpdateInstaller`(다운로드→번들 교체→재실행). 릴리스 zip 에셋 이름 규약 `SnapScreen-vX.Y.Z.zip`을 바꾸면 구버전 업데이터가 깨진다
```

- [ ] **Step 3: 버전 범프 (0.2.0)**

- `AppInfo.swift`: `version = "0.2.0"`
- `Resources/Info.plist`: `CFBundleShortVersionString` → `0.2.0`, `CFBundleVersion` → `2`

- [ ] **Step 4: 최종 검증**

```bash
swift test                        # 35개 PASS
Scripts/bundle.sh release         # OK
file -I docs/manual-test-checklist.md CLAUDE.md   # utf-8
```

- [ ] **Step 5: Commit**

```bash
git add docs/ CLAUDE.md Sources/ Resources/
git commit -m "chore: 업데이트 체크리스트 + CLAUDE.md 갱신 + v0.2.0 버전 범프"
```

---

### Task 7: PR 생성

- [ ] **Step 1: push + PR**

```bash
git push -u origin feature/in-app-update
gh pr create --title "feat: 인앱 업데이트 (버전 표시 + 최신 릴리스 확인 + 원클릭 업그레이드)" --body "$(cat <<'EOF'
## Summary
- 설정 창 "정보" 섹션: 현재 버전 + 최신 릴리스 상태 + 업데이트 확인/업그레이드 버튼
- 앱 시작 시 GitHub Releases 자동 확인 (실패 시 조용히 무시), 새 버전 발견 시 메뉴바에 "업데이트 가능 (vX.Y.Z)…" 항목
- 업그레이드 클릭 → zip 다운로드 → ditto 해제 → 버전 검증 → 번들 교체(롤백 지원) → 재실행
- 업데이트 후 첫 실행에 화면 기록 권한 재승인 안내 (ad-hoc 서명 제약)
- v0.2.0 버전 범프

## Test plan
- [ ] `swift test` 35개 통과 (UpdateChecker 단위 테스트 8개 포함)
- [ ] v0.2.0 릴리스 후 v0.1.0 → v0.2.0 업그레이드 E2E (manual-test-checklist §11)
EOF
)"
```

---

## 실행 순서와 검증 한계

- Task 1(체커) → 2(상태+배선) → 3(설치기) → 4(설정 UI) → 5(메뉴바) → 6(문서+범프) → 7(PR). 순차 의존.
- **업그레이드 E2E는 이 기능이 담긴 v0.2.0을 릴리스한 후에야 검증 가능** (구버전 v0.1.0을 설치하고 업그레이드): 머지 → `make release VERSION=v0.2.0` → v0.1.0 zip을 받아 실행 → 업데이트 플로우 확인. 이 계획의 범위는 머지까지이고 E2E는 체크리스트 §11로 이관.
```
