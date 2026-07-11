# 히스토리 관리(전체 비우기 + 보관 개수) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 최근 캡처 히스토리를 한 번에 비우고, 보관 개수를 설정에서 조절할 수 있게 한다.

**Architecture:** `HistoryStore`에 `clear()`/`updateLimit(_:)`를 추가(limit 가변화)하고, `SettingsStore.historyLimit`(UserDefaults)를 `AppDelegate`가 구독해 스토어에 반영한다. 홈 창 헤더의 "모두 지우기" 버튼이 확인 후 `clear()`를 호출.

**Tech Stack:** Swift, Combine, SwiftUI, XCTest.

---

## 파일 구조

| 파일 | 책임 | 상태 |
|---|---|---|
| `History/HistoryStore.swift` | `limit` 가변 + `clear()`/`updateLimit(_:)` | 수정 |
| `Settings/SettingsStore.swift` | `historyLimit: Int`(UserDefaults) | 수정 |
| `Settings/SettingsView.swift` | "히스토리" 섹션 + 보관 개수 Picker | 수정 |
| `AppCore/AppDelegate.swift` | 초기 limit 주입 + `$historyLimit` 구독→`updateLimit` | 수정 |
| `Home/HomeView.swift` | "모두 지우기" 버튼 + 확인 다이얼로그 | 수정 |
| `Tests/SnapScreenKitTests/HistoryStoreTests.swift` | `clear`/`updateLimit` 테스트 | 수정 |
| `Tests/SnapScreenKitTests/SettingsStoreTests.swift` | `historyLimit` 왕복 테스트 | 신규 |
| `docs/manual-test-checklist.md`, `Support/AppInfo.swift`, `Resources/Info.plist` | 문서·버전 | 수정 |

---

### Task 1: HistoryStore clear/updateLimit (TDD)

**Files:**
- Modify: `Sources/SnapScreenKit/History/HistoryStore.swift`
- Test: `Tests/SnapScreenKitTests/HistoryStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 추가**

`HistoryStoreTests`에 메서드 추가(기존 `waitUntil`/`solidImage` 헬퍼 재사용):

```swift
    func testClearRemovesAllAndPersists() async throws {
        let store = HistoryStore(directory: dir, limit: 50)
        store.add(image: solidImage(), scale: 1, id: UUID(), date: Date())
        store.add(image: solidImage(), scale: 1, id: UUID(), date: Date())
        try await waitUntil { store.entries.count == 2 }

        store.clear()
        XCTAssertTrue(store.entries.isEmpty)
        let reloaded = HistoryStore(directory: dir, limit: 50)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    func testUpdateLimitTrimsOldest() async throws {
        let store = HistoryStore(directory: dir, limit: 50)
        var ids: [UUID] = []
        for i in 0..<5 {
            let id = UUID(); ids.append(id)
            store.add(image: solidImage(), scale: 1, id: id, date: Date(timeIntervalSince1970: Double(i)))
        }
        try await waitUntil { store.entries.count == 5 }

        store.updateLimit(2)
        XCTAssertEqual(store.entries.count, 2)
        // 가장 최신 2개(i=3,4)만 남음
        XCTAssertTrue(store.entries.contains { $0.id == ids[4] })
        XCTAssertFalse(store.entries.contains { $0.id == ids[0] })
        let reloaded = HistoryStore(directory: dir, limit: 2)
        XCTAssertEqual(reloaded.entries.count, 2)
    }

    func testUpdateLimitLargerKeepsAll() async throws {
        let store = HistoryStore(directory: dir, limit: 50)
        store.add(image: solidImage(), scale: 1, id: UUID(), date: Date())
        try await waitUntil { store.entries.count == 1 }
        store.updateLimit(100)
        XCTAssertEqual(store.entries.count, 1)
    }
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter HistoryStoreTests`
Expected: 컴파일 실패 (`clear`/`updateLimit` 없음).

- [ ] **Step 3: HistoryStore 구현**

`limit` 선언을 가변으로: `private let limit: Int` → `private var limit: Int`

메서드 추가(`remove(id:)` 다음):

```swift
    /// 히스토리 전체 삭제 (파일 + 메타)
    public func clear() {
        for entry in entries { archive.delete(id: entry.id) }
        entries = []
        archive.writeIndex(entries)
    }

    /// 보관 개수 변경. 줄이면 초과분(오래된 것부터)을 즉시 삭제한다.
    public func updateLimit(_ newLimit: Int) {
        limit = newLimit
        while entries.count > limit {
            let removed = entries.removeLast()
            archive.delete(id: removed.id)
        }
        archive.writeIndex(entries)
    }
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter HistoryStoreTests`
Expected: 기존 3 + 신규 3 = 6 PASS.

- [ ] **Step 5: 커밋**

```bash
git add Sources/SnapScreenKit/History/HistoryStore.swift Tests/SnapScreenKitTests/HistoryStoreTests.swift
git commit -m "feat: HistoryStore clear/updateLimit (전체 비우기·보관 개수)"
```

---

### Task 2: SettingsStore.historyLimit (TDD)

**Files:**
- Modify: `Sources/SnapScreenKit/Settings/SettingsStore.swift`
- Test: `Tests/SnapScreenKitTests/SettingsStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/SnapScreenKitTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import SnapScreenKit

final class SettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "settings-test-\(UUID().uuidString)")!
        return d
    }

    func testHistoryLimitDefaultsTo50() {
        let store = SettingsStore(defaults: makeDefaults())
        store.load()
        XCTAssertEqual(store.historyLimit, 50)
    }

    func testHistoryLimitPersistsAndReloads() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.load()
        store.historyLimit = 100

        let reloaded = SettingsStore(defaults: defaults)
        reloaded.load()
        XCTAssertEqual(reloaded.historyLimit, 100)
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter SettingsStoreTests`
Expected: 컴파일 실패 (`historyLimit` 없음).

- [ ] **Step 3: SettingsStore 구현**

`Key` enum에 추가:
```swift
        static let historyLimit = "historyLimit"
```

`@Published` 프로퍼티 추가(`filenamePrefix` 다음):
```swift
    @Published public var historyLimit: Int = 50 {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }
```

`load()`에 추가:
```swift
        let storedLimit = defaults.integer(forKey: Key.historyLimit)
        historyLimit = storedLimit == 0 ? 50 : storedLimit
```
(`integer(forKey:)`는 미설정 시 0을 반환하므로 0이면 기본 50으로 처리)

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter SettingsStoreTests`
Expected: 2 tests PASS.

- [ ] **Step 5: 커밋**

```bash
git add Sources/SnapScreenKit/Settings/SettingsStore.swift Tests/SnapScreenKitTests/SettingsStoreTests.swift
git commit -m "feat: SettingsStore.historyLimit (보관 개수 저장)"
```

---

### Task 3: 설정 UI + AppDelegate 연동

**Files:**
- Modify: `Sources/SnapScreenKit/Settings/SettingsView.swift`
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`

- [ ] **Step 1: SettingsView에 "히스토리" 섹션 추가**

`SettingsView`의 Form에서 "저장" `Section` **다음**에 추가:

```swift
            Section("히스토리") {
                Picker("보관 개수", selection: $settings.historyLimit) {
                    ForEach([20, 50, 100, 200], id: \.self) { Text("\($0)개").tag($0) }
                }
            }
```

- [ ] **Step 2: AppDelegate에 초기 limit 주입 + 구독**

`import AppKit` 아래에 `import Combine` 추가.

`historyStore` 프로퍼티 다음에 구독 토큰 추가:
```swift
    private var historyLimitCancellable: AnyCancellable?
```

`historyStore = HistoryStore(directory: historyDir)` 를 아래로 교체(초기 limit 주입):
```swift
        historyStore = HistoryStore(directory: historyDir, limit: coordinator.settings.historyLimit)
        coordinator.historyStore = historyStore
        historyLimitCancellable = coordinator.settings.$historyLimit.sink { [weak historyStore] limit in
            historyStore?.updateLimit(limit)
        }
```
(`coordinator.settings`는 `CaptureCoordinator.init`에서 `settings.load()`로 저장값이 이미 로드된 상태다. `sink`는 구독 즉시 현재값도 방출하지만 `updateLimit`은 멱등이라 무해하다.)

- [ ] **Step 3: 빌드**

Run: `rm -rf .build && swift build 2>&1 | grep -ci warning`
Expected: `0`
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` → 이전 대비 +5 (History 3 + Settings 2)

- [ ] **Step 4: 커밋**

```bash
git add Sources/SnapScreenKit/Settings/SettingsView.swift Sources/SnapScreenKit/AppCore/AppDelegate.swift
git commit -m "feat: 설정 히스토리 보관 개수 Picker + 스토어 연동"
```

---

### Task 4: 홈 창 "모두 지우기"

**Files:**
- Modify: `Sources/SnapScreenKit/Home/HomeView.swift`

- [ ] **Step 1: showClearConfirm 상태 추가**

`@State private var hoveredID: UUID?` 다음 줄에 추가:
```swift
    @State private var showClearConfirm = false
```

- [ ] **Step 2: "최근 캡처" 헤더에 버튼 + 다이얼로그**

현재 헤더 `HStack`(최근 캡처 라벨 + Spacer):
```swift
            HStack {
                Text("최근 캡처").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }
```
를 아래로 교체:
```swift
            HStack {
                Text("최근 캡처").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !history.entries.isEmpty {
                    Button("모두 지우기") { showClearConfirm = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .confirmationDialog("최근 캡처를 모두 지울까요?",
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("모두 지우기", role: .destructive) { history.clear() }
                Button("취소", role: .cancel) {}
            }
```

- [ ] **Step 3: 빌드 + 로컬 실행 확인**

Run: `rm -rf .build && swift build 2>&1 | grep -ci warning` → 0
Run: `swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1` → 유지
Run: `Scripts/run.sh` → 홈 창 헤더 "모두 지우기" → 확인 다이얼로그 → 비워짐, 설정에서 보관 개수 변경 시 반영(수동)

- [ ] **Step 4: 커밋**

```bash
git add Sources/SnapScreenKit/Home/HomeView.swift
git commit -m "feat: 홈 창 최근 캡처 모두 지우기 (확인 다이얼로그)"
```

---

### Task 5: 문서 + v0.11.0 범프 + PR

**Files:**
- Modify: `docs/manual-test-checklist.md`
- Modify: `Sources/SnapScreenKit/Support/AppInfo.swift`, `Resources/Info.plist`

- [ ] **Step 1: 체크리스트 §19 보강**

`docs/manual-test-checklist.md`의 "## 19. 최근 캡처 (히스토리)" 목록 끝에 추가:

```markdown
- [ ] 헤더의 "모두 지우기"를 누르면 확인 후 히스토리가 전부 비워진다
- [ ] 설정 > 히스토리에서 보관 개수를 줄이면 오래된 항목부터 즉시 사라진다
```

- [ ] **Step 2: 버전 범프**

- `Sources/SnapScreenKit/Support/AppInfo.swift`: `version = "0.11.0"`
- Info.plist:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.11.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 21" Resources/Info.plist
```

- [ ] **Step 3: 최종 검증**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1        # 78 + 5 = 83 PASS
rm -rf .build && swift build 2>&1 | grep -ci warning               # 0
Scripts/bundle.sh release                                          # OK
file -I docs/manual-test-checklist.md                              # utf-8
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist  # 0.11.0
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist              # 21
```

- [ ] **Step 4: Commit + Push + PR**

```bash
git add docs/ Sources/ Resources/
git commit -m "$(cat <<'EOF'
chore: 히스토리 관리 문서 + v0.11.0 버전 범프

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
git push -u origin feat/history-management
gh pr create --title "feat: 히스토리 관리 (전체 비우기 + 보관 개수)" --body "$(cat <<'EOF'
## Summary
- 홈 창 "최근 캡처" 헤더에 "모두 지우기" 버튼 + 확인 다이얼로그 → 전체 삭제
- 설정 창 "히스토리" 섹션에 보관 개수 Picker(20/50/100/200, 기본 50), 변경 시 즉시 트림
- `HistoryStore.clear()`/`updateLimit(_:)`, `SettingsStore.historyLimit`(UserDefaults), AppDelegate 구독 연동
- v0.11.0 범프

## 설계/계획
- Spec: `docs/superpowers/specs/2026-07-11-history-management-design.md`
- Plan: `docs/superpowers/plans/2026-07-11-history-management.md`

## Test plan
- [x] 단위: HistoryStore clear/updateLimit(3), SettingsStore historyLimit(2), 전체 83개 통과, clean 빌드 경고 0
- [ ] 수동: 모두 지우기·보관 개수 변경 즉시 반영 (checklist §19)
EOF
)"
```
커밋 메시지 끝에 빈 줄 후 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` 추가. `--reviewer` 플래그 쓰지 말 것.

## 실행 순서와 검증 한계

- Task 1(store) → 2(settings) → 3(설정 UI+연동) → 4(홈 버튼) → 5(문서·범프·PR).
- 설정 Picker·홈 버튼·다이얼로그는 GUI라 자동 테스트 불가 → 수동 §19. 단위 테스트는 `clear`/`updateLimit`/`historyLimit` 로직 커버.
- 릴리스(`make release VERSION=v0.11.0`)는 PR 머지 후 별도.
