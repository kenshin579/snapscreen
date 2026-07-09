# 최근 캡처 갤러리/히스토리 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 모든 캡처를 자동 보관해 홈 창 갤러리에서 다시 열 수 있는 최근 캡처 히스토리를 추가한다(최근 50개).

**Architecture:** 순수 동기 IO(`HistoryArchive`, 디렉터리 주입 → 단위 테스트)와 상태 래퍼(`HistoryStore`, `@MainActor ObservableObject`)를 분리한다. `CaptureCoordinator.handleCaptured`가 캡처 원본을 백그라운드로 저장하고, 홈 창(`HomeView`) 그리드가 썸네일을 표시한다. 클릭 시 원본을 로드해 기존 편집기로 재열기.

**Tech Stack:** Swift, CoreGraphics/ImageIO, Foundation, SwiftUI, XCTest.

---

## 파일 구조

| 파일 | 책임 | 상태 |
|---|---|---|
| `History/HistoryEntry.swift` | 항목 메타(`id`/`date`/`scale`), `Codable` | 신규 |
| `History/HistoryArchive.swift` | 동기 파일 IO(원본/썸네일/index 저장·로드·삭제), 디렉터리 주입 | 신규 |
| `History/HistoryStore.swift` | `@MainActor ObservableObject` — entries 관리, 50개 롤링, 비동기 add | 신규 |
| `AppCore/CaptureCoordinator.swift` | `handleCaptured` 히스토리 기록 + `openFromHistory` 재열기 진입점 | 수정 |
| `AppCore/AppDelegate.swift` | `HistoryStore` 생성·주입 | 수정 |
| `Home/HomeView.swift` | 최근 캡처 그리드 + 클릭/우클릭 | 수정 |
| `Home/HomeWindowController.swift` | store/콜백 주입, 창 세로 확대 | 수정 |
| `Tests/SnapScreenKitTests/HistoryArchiveTests.swift` | IO 단위 테스트 | 신규 |
| `Tests/SnapScreenKitTests/HistoryStoreTests.swift` | 롤링/remove/add 테스트 | 신규 |
| `docs/manual-test-checklist.md`, `README.md`, `CLAUDE.md`, `Support/AppInfo.swift`, `Resources/Info.plist` | 문서·버전 | 수정 |

---

### Task 1: HistoryEntry + HistoryArchive (순수 IO, TDD)

**Files:**
- Create: `Sources/SnapScreenKit/History/HistoryEntry.swift`
- Create: `Sources/SnapScreenKit/History/HistoryArchive.swift`
- Test: `Tests/SnapScreenKitTests/HistoryArchiveTests.swift`

- [ ] **Step 1: HistoryEntry 작성** (테스트에서 필요하므로 먼저)

`Sources/SnapScreenKit/History/HistoryEntry.swift`:

```swift
import Foundation
import CoreGraphics

/// 히스토리 항목 메타데이터. 실제 이미지는 <id>.png / <id>.thumb.png로 저장된다.
public struct HistoryEntry: Codable, Equatable, Identifiable {
    public let id: UUID
    public let date: Date
    public let scale: CGFloat   // 재편집 시 Retina 배율 복원에 필수

    public init(id: UUID, date: Date, scale: CGFloat) {
        self.id = id
        self.date = date
        self.scale = scale
    }
}
```

- [ ] **Step 2: 실패하는 테스트 작성**

`Tests/SnapScreenKitTests/HistoryArchiveTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnapScreenKit

final class HistoryArchiveTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-test-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func solidImage(_ w: Int = 40, _ h: Int = 30) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    func testWriteCreatesFilesAndEntry() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        let entry = try archive.write(image: solidImage(), scale: 2, id: id, date: Date())
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.scale, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.pngURL(id).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.thumbURL(id).path))
    }

    func testLoadImageRoundTrips() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        _ = try archive.write(image: solidImage(40, 30), scale: 1, id: id, date: Date())
        let loaded = archive.loadImage(id: id)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.width, 40)
        XCTAssertEqual(loaded?.height, 30)
    }

    func testIndexRoundTripsAndSelfHeals() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        _ = try archive.write(image: solidImage(), scale: 1, id: id, date: Date())
        let phantom = HistoryEntry(id: UUID(), date: Date(), scale: 1) // 파일 없는 항목
        let real = HistoryEntry(id: id, date: Date(), scale: 1)
        archive.writeIndex([phantom, real])
        let loaded = archive.loadIndex()
        // 파일 있는 항목만 남는다(자가 치유)
        XCTAssertEqual(loaded.map(\.id), [id])
    }

    func testCorruptIndexReturnsEmpty() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: dir.appendingPathComponent("index.json"))
        let archive = HistoryArchive(directory: dir)
        XCTAssertEqual(archive.loadIndex(), [])
    }

    func testDeleteRemovesFiles() throws {
        let archive = HistoryArchive(directory: dir)
        let id = UUID()
        _ = try archive.write(image: solidImage(), scale: 1, id: id, date: Date())
        archive.delete(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.pngURL(id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.thumbURL(id).path))
    }
}
```

- [ ] **Step 3: 테스트 실패 확인**

Run: `swift test --filter HistoryArchiveTests`
Expected: 컴파일 실패 (`HistoryArchive` 없음).

- [ ] **Step 4: HistoryArchive 구현**

`Sources/SnapScreenKit/History/HistoryArchive.swift`:

```swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum HistoryError: Error { case encodeFailed }

/// 히스토리 파일 IO. 전부 동기·nonisolated라 임시 디렉터리로 단위 테스트 가능.
struct HistoryArchive: Sendable {
    let directory: URL

    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    func pngURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).png") }
    func thumbURL(_ id: UUID) -> URL { directory.appendingPathComponent("\(id.uuidString).thumb.png") }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 원본 PNG + 썸네일 저장. 성공 시 메타 반환.
    func write(image: CGImage, scale: CGFloat, id: UUID, date: Date) throws -> HistoryEntry {
        try ensureDirectory()
        guard let png = PNGEncoder.encode(image, scale: scale) else { throw HistoryError.encodeFailed }
        try png.write(to: pngURL(id))
        if let thumb = Self.thumbnailPNG(from: png, maxPixel: 320) {
            try? thumb.write(to: thumbURL(id)) // 썸네일 실패는 치명적 아님(원본으로 대체 가능)
        }
        return HistoryEntry(id: id, date: date, scale: scale)
    }

    func loadImage(id: UUID) -> CGImage? {
        guard let data = try? Data(contentsOf: pngURL(id)),
              let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return img
    }

    /// index.json 로드 + 자가 치유(원본 파일 없는 항목 제거). 파싱 실패 시 빈 배열.
    func loadIndex() -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return [] }
        return entries.filter { FileManager.default.fileExists(atPath: pngURL($0.id).path) }
    }

    func writeIndex(_ entries: [HistoryEntry]) {
        try? ensureDirectory()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: indexURL)
    }

    func delete(id: UUID) {
        try? FileManager.default.removeItem(at: pngURL(id))
        try? FileManager.default.removeItem(at: thumbURL(id))
    }

    static func thumbnailPNG(from pngData: Data, maxPixel: CGFloat) -> Data? {
        guard let src = CGImageSourceCreateWithData(pngData as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, thumb, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
```

- [ ] **Step 5: 테스트 통과 확인**

Run: `swift test --filter HistoryArchiveTests`
Expected: 5 tests PASS.

- [ ] **Step 6: 커밋**

```bash
git add Sources/SnapScreenKit/History/HistoryEntry.swift Sources/SnapScreenKit/History/HistoryArchive.swift Tests/SnapScreenKitTests/HistoryArchiveTests.swift
git commit -m "feat: 히스토리 파일 IO (HistoryArchive) + 메타 모델"
```

---

### Task 2: HistoryStore (상태 래퍼, TDD)

**Files:**
- Create: `Sources/SnapScreenKit/History/HistoryStore.swift`
- Test: `Tests/SnapScreenKitTests/HistoryStoreTests.swift`

- [ ] **Step 1: 실패하는 테스트 작성**

`Tests/SnapScreenKitTests/HistoryStoreTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import SnapScreenKit

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-store-\(UUID().uuidString)")
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }
    private func solidImage() -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        return ctx.makeImage()!
    }

    func testAddInsertsNewestFirst() async throws {
        let store = HistoryStore(directory: dir, limit: 50)
        store.add(image: solidImage(), scale: 1, id: UUID(), date: Date(timeIntervalSince1970: 100))
        store.add(image: solidImage(), scale: 1, id: UUID(), date: Date(timeIntervalSince1970: 200))
        try await waitUntil { store.entries.count == 2 }
        XCTAssertEqual(store.entries.first?.date, Date(timeIntervalSince1970: 200)) // 최신 먼저
    }

    func testRollingDropsOldest() async throws {
        let store = HistoryStore(directory: dir, limit: 3)
        var ids: [UUID] = []
        for i in 0..<4 {
            let id = UUID(); ids.append(id)
            store.add(image: solidImage(), scale: 1, id: id, date: Date(timeIntervalSince1970: Double(i)))
        }
        try await waitUntil { store.entries.count == 3 }
        XCTAssertFalse(store.entries.contains { $0.id == ids[0] }) // 가장 오래된 것 제거
    }

    func testRemoveDeletesEntryAndReloadsEmpty() async throws {
        let store = HistoryStore(directory: dir, limit: 50)
        let id = UUID()
        store.add(image: solidImage(), scale: 3, id: id, date: Date())
        try await waitUntil { store.entries.count == 1 }
        XCTAssertEqual(store.entries.first?.scale, 3) // scale 왕복

        store.remove(id: id)
        XCTAssertTrue(store.entries.isEmpty)
        // 새 store로 재로드해도 비어 있음(index/파일 삭제 확인)
        let reloaded = HistoryStore(directory: dir, limit: 50)
        XCTAssertTrue(reloaded.entries.isEmpty)
    }

    /// 조건이 참이 될 때까지 최대 2초 폴링(add가 비동기 인코딩이라)
    private func waitUntil(_ cond: @escaping () -> Bool) async throws {
        for _ in 0..<200 {
            if cond() { return }
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        XCTFail("조건 미충족(timeout)")
    }
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `swift test --filter HistoryStoreTests`
Expected: 컴파일 실패 (`HistoryStore` 없음).

- [ ] **Step 3: HistoryStore 구현**

`Sources/SnapScreenKit/History/HistoryStore.swift`:

```swift
import Foundation
import CoreGraphics

/// 히스토리 상태 래퍼. entries(최신순)를 노출하고 50개 상한 롤링을 관리한다.
/// 인코딩/디스크 쓰기는 백그라운드에서 수행하고 결과만 메인에서 반영(캡처 흐름 비차단).
@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var entries: [HistoryEntry] = []
    private let archive: HistoryArchive
    private let limit: Int

    public init(directory: URL, limit: Int = 50) {
        self.archive = HistoryArchive(directory: directory)
        self.limit = limit
        entries = archive.loadIndex().sorted { $0.date > $1.date }
    }

    public func add(image: CGImage, scale: CGFloat, id: UUID = UUID(), date: Date = Date()) {
        let archive = self.archive
        DispatchQueue.global(qos: .utility).async {
            guard let entry = try? archive.write(image: image, scale: scale, id: id, date: date) else { return }
            Task { @MainActor in self.insert(entry) }
        }
    }

    private func insert(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }        // 동일 id 재추가 방지
        entries.append(entry)
        entries.sort { $0.date > $1.date }             // 최신순
        while entries.count > limit {
            let removed = entries.removeLast()
            archive.delete(id: removed.id)
        }
        archive.writeIndex(entries)
    }

    public func loadImage(id: UUID) -> CGImage? { archive.loadImage(id: id) }
    public func thumbnailURL(id: UUID) -> URL { archive.thumbURL(id) }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        archive.delete(id: id)
        archive.writeIndex(entries)
    }
}
```

- [ ] **Step 4: 테스트 통과 확인**

Run: `swift test --filter HistoryStoreTests`
Expected: 3 tests PASS. (`DispatchQueue.global` + `Task { @MainActor }` 패턴은 기존 `TextRecognizer`와 동일해 CGImage 캡처 경고가 없다. clean 빌드 경고 0 확인.)

- [ ] **Step 5: 커밋**

```bash
git add Sources/SnapScreenKit/History/HistoryStore.swift Tests/SnapScreenKitTests/HistoryStoreTests.swift
git commit -m "feat: HistoryStore (50개 롤링, 비동기 저장)"
```

---

### Task 3: 캡처 기록 + 재열기 통합

**Files:**
- Modify: `Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift`
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`

- [ ] **Step 1: CaptureCoordinator에 히스토리 기록 + 재열기 진입점**

`historyStore` 프로퍼티 추가(`policyManager` 근처):

```swift
    public var historyStore: HistoryStore?
```

`handleCaptured`를 아래로 교체하고 `openEditor`/`openFromHistory` 추가:

```swift
    func handleCaptured(_ result: CaptureResult) {
        openEditor(result)
        historyStore?.add(image: result.image, scale: result.scale)
    }

    /// 히스토리 항목을 편집기로 다시 연다(재기록 없음).
    public func openFromHistory(image: CGImage, scale: CGFloat) {
        openEditor(CaptureResult(image: image, scale: scale))
    }

    private func openEditor(_ result: CaptureResult) {
        var controller: EditorWindowController?
        controller = EditorWindowController(result: result, settings: settings,
                                            policyManager: policyManager) { [weak self] in
            self?.editors.removeAll { $0 === controller }
        }
        if let controller { editors.append(controller) }
    }
```

- [ ] **Step 2: AppDelegate에서 HistoryStore 생성·주입**

`AppDelegate`에 프로퍼티 추가:

```swift
    private var historyStore: HistoryStore!
```

`applicationDidFinishLaunching`에서 `coordinator` 생성 직후, 홈 창 생성 **앞**에 추가:

```swift
        let historyDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnapScreen/History", isDirectory: true)
        historyStore = HistoryStore(directory: historyDir)
        coordinator.historyStore = historyStore
```

(홈 창 생성 부분은 Task 4에서 store/onOpenEntry를 함께 주입하도록 수정한다.)

- [ ] **Step 3: 빌드**

Run: `swift build 2>&1 | grep -ci warning`
Expected: `0`

- [ ] **Step 4: 커밋**

```bash
git add Sources/SnapScreenKit/AppCore/CaptureCoordinator.swift Sources/SnapScreenKit/AppCore/AppDelegate.swift
git commit -m "feat: 캡처 시 히스토리 기록 + 재열기 진입점"
```

---

### Task 4: 홈 창 갤러리 UI

**Files:**
- Modify: `Sources/SnapScreenKit/Home/HomeView.swift`
- Modify: `Sources/SnapScreenKit/Home/HomeWindowController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`

- [ ] **Step 1: HomeView에 갤러리 섹션 추가**

`HomeView`를 아래로 교체(store/콜백 주입 + 그리드 추가):

```swift
import SwiftUI
import KeyboardShortcuts

/// 홈 창 내용: 캡처 버튼 3개 + 최근 캡처 그리드 + 하단 버전.
public struct HomeView: View {
    let onCapture: @MainActor (CaptureMode) -> Void
    @ObservedObject var history: HistoryStore
    let onOpenEntry: @MainActor (HistoryEntry) -> Void

    public init(onCapture: @escaping @MainActor (CaptureMode) -> Void,
                history: HistoryStore,
                onOpenEntry: @escaping @MainActor (HistoryEntry) -> Void) {
        self.onCapture = onCapture
        self.history = history
        self.onOpenEntry = onOpenEntry
    }

    private struct Item {
        let mode: CaptureMode
        let symbol: String
        let title: String
        let shortcutName: KeyboardShortcuts.Name
    }
    private let items: [Item] = [
        Item(mode: .area, symbol: "rectangle.dashed", title: "영역", shortcutName: .captureArea),
        Item(mode: .window, symbol: "macwindow", title: "창", shortcutName: .captureWindow),
        Item(mode: .fullScreen, symbol: "display", title: "전체 화면", shortcutName: .captureFullScreen)
    ]
    private let columns = [GridItem(.adaptive(minimum: 116), spacing: 10)]

    public var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                ForEach(items, id: \.symbol) { item in
                    Button { onCapture(item.mode) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: item.symbol).font(.system(size: 28))
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(KeyboardShortcuts.getShortcut(for: item.shortcutName)?.description ?? "미설정")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
                    .accessibilityLabel(item.title)
                    .accessibilityHint("스크린샷을 캡처합니다")
                }
            }

            Divider()

            HStack {
                Text("최근 캡처").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
            }

            if history.entries.isEmpty {
                Text("아직 캡처가 없습니다")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(history.entries) { entry in
                            thumbnail(entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 260)
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

    @ViewBuilder
    private func thumbnail(_ entry: HistoryEntry) -> some View {
        let image = NSImage(contentsOf: history.thumbnailURL(id: entry.id))
        Button { onOpenEntry(entry) } label: {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 78)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(entry.date.formatted(date: .abbreviated, time: .shortened))
        .contextMenu {
            Button("삭제", role: .destructive) { history.remove(id: entry.id) }
        }
    }
}
```

- [ ] **Step 2: HomeWindowController 주입 업데이트**

`HomeWindowController.init`을 아래로 교체(store/onOpenEntry 전달):

```swift
    public init(policyManager: ActivationPolicyManager,
                history: HistoryStore,
                onCapture: @escaping @MainActor (CaptureMode) -> Void,
                onOpenEntry: @escaping @MainActor (HistoryEntry) -> Void) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: HomeView(
            onCapture: onCapture, history: history, onOpenEntry: onOpenEntry))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
    }
```

- [ ] **Step 3: AppDelegate 홈 창 생성 업데이트**

`HomeWindowController(...)` 생성을 아래로 교체:

```swift
        homeWindowController = HomeWindowController(
            policyManager: activationPolicyManager,
            history: historyStore,
            onCapture: { [weak coordinator] mode in coordinator?.beginCapture(mode) },
            onOpenEntry: { [weak coordinator, weak self] entry in
                guard let coordinator, let self else { return }
                if let image = self.historyStore.loadImage(id: entry.id) {
                    coordinator.openFromHistory(image: image, scale: entry.scale)
                } else {
                    Notifier.show(title: "열 수 없음", body: "원본 파일을 찾지 못했습니다")
                    self.historyStore.remove(id: entry.id)
                }
            })
```

- [ ] **Step 4: 빌드 + 로컬 실행**

Run: `rm -rf .build && swift build 2>&1 | grep -ci warning` → 0
Run: `Scripts/run.sh` → 캡처 후 홈 창(메뉴바 "홈…" 또는 재실행)에서 그리드 확인, 클릭 재편집, 우클릭 삭제(수동)

- [ ] **Step 5: 커밋**

```bash
git add Sources/SnapScreenKit/Home/HomeView.swift Sources/SnapScreenKit/Home/HomeWindowController.swift Sources/SnapScreenKit/AppCore/AppDelegate.swift
git commit -m "feat: 홈 창 최근 캡처 갤러리 (썸네일 그리드 + 클릭 재편집 + 삭제)"
```

---

### Task 5: 문서 + v0.10.0 범프 + PR

**Files:**
- Modify: `docs/manual-test-checklist.md`, `README.md`, `CLAUDE.md`
- Modify: `Sources/SnapScreenKit/Support/AppInfo.swift`, `Resources/Info.plist`

- [ ] **Step 1: 체크리스트 "19. 최근 캡처" 추가**

`docs/manual-test-checklist.md` 끝에:

```markdown
## 19. 최근 캡처 (히스토리)

- [ ] 캡처하면 홈 창 "최근 캡처"에 썸네일이 곧 나타난다(저장 안 해도)
- [ ] 썸네일을 클릭하면 편집기로 다시 열리고 배율(선명도)이 정상이다
- [ ] 우클릭 → 삭제로 항목이 사라진다
- [ ] 51번째 캡처 시 가장 오래된 항목이 사라진다(최근 50개 유지)
- [ ] 앱을 재시작해도 히스토리가 유지된다
- [ ] 히스토리가 비어 있으면 "아직 캡처가 없습니다"가 보인다
```

- [ ] **Step 2: 버전 범프**

- `Sources/SnapScreenKit/Support/AppInfo.swift`: `version = "0.10.0"`
- Info.plist:
```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString 0.10.0" Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 16" Resources/Info.plist
```

- [ ] **Step 3: README/CLAUDE.md 갱신**

- `README.md`: 기능 목록에 "최근 캡처 갤러리: 저장하지 않은 캡처도 홈 창에서 다시 열기(최근 50개)" 추가
- `CLAUDE.md`: 아키텍처에 `History/` 모듈 한 줄 — `HistoryArchive`(동기 IO, `~/Library/Application Support/SnapScreen/History`)/`HistoryStore`(@MainActor, 50개 롤링)로 캡처를 자동 보관하고 홈 창 그리드에서 재편집, 저장은 `CaptureCoordinator.handleCaptured`에서 백그라운드 수행한다는 취지.

- [ ] **Step 4: 최종 검증**

```bash
swift test 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1        # 기존 69 + Archive 5 + Store 3 = 77 PASS
rm -rf .build && swift build 2>&1 | grep -ci warning               # 0
Scripts/bundle.sh release                                          # OK
file -I README.md docs/manual-test-checklist.md CLAUDE.md          # utf-8
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist  # 0.10.0
/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist              # 16
```

- [ ] **Step 5: Commit + Push + PR**

```bash
git add docs/ README.md CLAUDE.md Sources/ Resources/
git commit -m "chore: 최근 캡처 히스토리 문서 + v0.10.0 버전 범프"
git push -u origin feat/capture-history
gh pr create --title "feat: 최근 캡처 갤러리/히스토리" --body "$(cat <<'EOF'
## Summary
- 모든 캡처를 자동 보관해 홈 창 갤러리에서 다시 열 수 있는 히스토리 (최근 50개, 저장 안 해도 남음)
- `HistoryArchive`(동기 파일 IO: 원본 PNG + 썸네일 + index.json, 자가 치유) + `HistoryStore`(@MainActor, 50개 롤링, 백그라운드 저장)
- `CaptureCoordinator.handleCaptured`에서 백그라운드 기록, `openFromHistory`로 재열기(scale 보존)
- 홈 창에 썸네일 그리드 + 클릭 재편집 + 우클릭 삭제
- v0.10.0 범프

## 설계/계획
- Spec: `docs/superpowers/specs/2026-07-09-capture-history-design.md`
- Plan: `docs/superpowers/plans/2026-07-09-capture-history.md`

## Test plan
- [x] 단위: HistoryArchive(5), HistoryStore(3), 전체 77개 통과, clean 빌드 경고 0
- [ ] 수동: 캡처 시 갤러리 등장·클릭 재편집·삭제·50개 롤링·재시작 유지 (checklist §19)
EOF
)"
```

커밋 메시지 끝에 빈 줄 후 `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>` 추가. `--reviewer` 플래그 쓰지 말 것.

## 실행 순서와 검증 한계

- Task 1(IO) → 2(store) → 3(기록 통합) → 4(홈 UI) → 5(문서·범프·PR). Task 3·4는 AppDelegate를 함께 건드리므로 4에서 홈 창 생성까지 완성한다.
- 실제 캡처→갤러리→재편집·삭제·재시작 유지는 GUI라 자동 테스트 불가 → 수동 §19. 단위 테스트는 IO/롤링/재로드 로직을 커버.
- 릴리스(`make release VERSION=v0.10.0`)는 PR 머지 후 별도.
