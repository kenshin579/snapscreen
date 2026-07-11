# 홈 창 리디자인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 홈 창을 확정 디자인(인라인 투명 타이틀바 + 디자인 토큰 기반 캡처 타일 + 키캡 칩 + 설정 기어 푸터)으로 재구현하되 기존 캡처/스크롤/히스토리 로직은 유지한다.

**Architecture:** 공통 기반 PR #28의 `DesignTokens`·`KeycapChip`·`ShortcutKeycaps`를 홈에서 처음 소비한다. 홈 배경/타일 하이라이트 등 화면 고유 색을 `DesignTokens`에 추가(Task 1)한 뒤, 창 구조·콜백 배선·뷰 재스타일을 한 태스크(Task 2)로 처리한다. UI라 자동 테스트가 없으므로 `swift build`/`swift test`(회귀) + 실제 앱 실행 스모크로 검증한다.

**Tech Stack:** Swift, SwiftUI, AppKit(NSWindow 타이틀바), KeyboardShortcuts.

**참고 스펙:** `docs/superpowers/specs/2026-07-11-snapscreen-home-redesign-design.md`
**디자인 값 출처:** `docs/design/design_handoff_snapscreen_redesign/README.md` §1

---

## File Structure

- **Modify** `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift` (Task 1) — 홈 화면 고유 색 토큰 추가.
- **Modify** `Sources/SnapScreenKit/Home/HomeWindowController.swift` (Task 2) — 인라인 투명 타이틀바, `.fullSizeContentView`, `onOpenSettings` 파라미터.
- **Modify** `Sources/SnapScreenKit/AppCore/AppDelegate.swift` (Task 2) — `HomeWindowController` 생성부에 `onOpenSettings` 전달.
- **Modify** `Sources/SnapScreenKit/Home/HomeView.swift` (Task 2) — 전체 뷰 재스타일 + `onOpenSettings` 소비.

Task 1(토큰)이 Task 2(뷰)의 의존이므로 먼저 한다. 홈의 3개 코드 파일은 `onOpenSettings` 배선으로 서로 강결합되어 함께 바뀌어야 빌드가 통과하므로 한 태스크로 묶는다.

---

## Task 1: DesignTokens 홈 토큰 추가

**Files:**
- Modify: `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift`

**배경:** 홈 창 배경 그라디언트, 캡처 타일 내부 상단 하이라이트, 썸네일 hover 삭제 버튼 배경은 홈에서만 쓰는 화면 고유 색이다. 공통 기반 단계에서 "소비자가 생길 때 추가"로 미뤘던 토큰을 이제 추가한다.

- [ ] **Step 1: `DesignTokens.Colors`에 토큰 추가**

`Sources/SnapScreenKit/DesignSystem/DesignTokens.swift`의 `enum Colors { ... }` 안, 기존 `keycapText` 정의 다음 줄(닫는 `}` 직전)에 아래를 추가:

```swift

        // MARK: 홈 화면 고유
        /// 홈 창 배경 그라디언트 상단 — 라이트 #F7F7F9 / 다크 #2C2C30
        public static let homeBackgroundTop = dynamic(
            light: NSColor(hex: 0xF7F7F9),
            dark: NSColor(hex: 0x2C2C30))
        /// 홈 창 배경 그라디언트 하단 — 라이트 #F0F0F3 / 다크 #232327
        public static let homeBackgroundBottom = dynamic(
            light: NSColor(hex: 0xF0F0F3),
            dark: NSColor(hex: 0x232327))
        /// 캡처 타일 내부 상단 하이라이트 — 라이트 흰색 90% / 다크 흰색 8%
        public static let tileTopHighlight = dynamic(
            light: NSColor(white: 1, alpha: 0.9),
            dark: NSColor(white: 1, alpha: 0.08))
        /// 썸네일 hover 삭제 버튼 배경 — 검정 55% 고정(흰 아이콘 대비용, 라이트/다크 공통)
        public static let thumbDeleteButtonBackground = Color(nsColor: NSColor(white: 0, alpha: 0.55))
```

- [ ] **Step 2: 빌드 검증**

Run: `swift build`
Expected: `Build complete!` (오류·경고 없음).

- [ ] **Step 3: UTF-8 확인**

Run: `file -I Sources/SnapScreenKit/DesignSystem/DesignTokens.swift`
Expected: `charset=utf-8`.

- [ ] **Step 4: Commit**

```bash
git add Sources/SnapScreenKit/DesignSystem/DesignTokens.swift
git commit -m "feat: 홈 화면 고유 디자인 토큰(배경 그라디언트·타일 하이라이트·삭제버튼) 추가"
```

---

## Task 2: 홈 창 재구현 (창 + 배선 + 뷰)

**Files:**
- Modify: `Sources/SnapScreenKit/Home/HomeWindowController.swift`
- Modify: `Sources/SnapScreenKit/AppCore/AppDelegate.swift`
- Modify: `Sources/SnapScreenKit/Home/HomeView.swift`

**배경:** 세 파일은 `onOpenSettings` 콜백으로 강결합된다. `HomeView`가 파라미터를 받고 → `HomeWindowController`가 넘기고 → `AppDelegate`가 실제 `openSettings(nil)` 클로저를 공급한다. 함께 바꿔야 컴파일된다. 기존 캡처(`onCapture`)/히스토리 열기(`onOpenEntry`)/스크롤(`leadingID`·`scrollBy`)/hover 삭제 로직은 그대로 유지한다.

- [ ] **Step 1: `HomeWindowController.swift` 전체 교체**

파일 전체를 아래로 교체:

```swift
import AppKit
import SwiftUI

/// 홈 창. 표시 시 ActivationPolicyManager에 등록(독 표시), 닫힐 때 해제(창 0개면 독 숨김).
/// 인라인 투명 타이틀바: 트래픽 라이트는 시스템 것을 유지하고 타이틀바 배경은 본문(홈 그라디언트)에 녹인다.
@MainActor
public final class HomeWindowController: NSWindowController, NSWindowDelegate {
    private let policyManager: ActivationPolicyManager

    public init(policyManager: ActivationPolicyManager,
                history: HistoryStore,
                onCapture: @escaping @MainActor (CaptureMode) -> Void,
                onOpenEntry: @escaping @MainActor (HistoryEntry) -> Void,
                onOpenSettings: @escaping @MainActor () -> Void) {
        self.policyManager = policyManager
        let hosting = NSHostingController(rootView: HomeView(
            onCapture: onCapture, history: history,
            onOpenEntry: onOpenEntry, onOpenSettings: onOpenSettings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "SnapScreen"
        // 리사이즈 불가 + 인라인 타이틀바(콘텐츠가 타이틀바 아래까지 확장)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
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

- [ ] **Step 2: `AppDelegate.swift`의 HomeWindowController 생성부에 `onOpenSettings` 추가**

`AppDelegate.swift`에서 아래 블록을 찾아:

```swift
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

마지막 닫는 괄호 `})` 를 아래처럼 바꿔 `onOpenSettings` 인자를 추가:

```swift
            onOpenEntry: { [weak coordinator, weak self] entry in
                guard let coordinator, let self else { return }
                if let image = self.historyStore.loadImage(id: entry.id) {
                    coordinator.openFromHistory(image: image, scale: entry.scale)
                } else {
                    Notifier.show(title: "열 수 없음", body: "원본 파일을 찾지 못했습니다")
                    self.historyStore.remove(id: entry.id)
                }
            },
            onOpenSettings: { [weak self] in self?.openSettings(nil) })
```

- [ ] **Step 3: `HomeView.swift` 전체 교체**

파일 전체를 아래로 교체:

```swift
import SwiftUI
import KeyboardShortcuts

/// 홈 창 내용: 인라인 타이틀 + 캡처 타일 3개 + 최근 캡처 그리드 + 푸터(설정 기어/버전).
public struct HomeView: View {
    let onCapture: @MainActor (CaptureMode) -> Void
    @ObservedObject var history: HistoryStore
    let onOpenEntry: @MainActor (HistoryEntry) -> Void
    let onOpenSettings: @MainActor () -> Void

    public init(onCapture: @escaping @MainActor (CaptureMode) -> Void,
                history: HistoryStore,
                onOpenEntry: @escaping @MainActor (HistoryEntry) -> Void,
                onOpenSettings: @escaping @MainActor () -> Void) {
        self.onCapture = onCapture
        self.history = history
        self.onOpenEntry = onOpenEntry
        self.onOpenSettings = onOpenSettings
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
    // 현재 왼쪽(leading)에 정렬된 항목 id. 트랙패드·화살표 스크롤 모두 반영(.scrollPosition).
    @State private var leadingID: UUID?
    @State private var hoveredID: UUID?
    @State private var showClearConfirm = false
    @State private var viewportWidth: CGFloat = 0
    private let itemStride: CGFloat = 130 // 썸네일 120 + 간격 10

    /// 한 화면(뷰포트)에 들어가는 썸네일 수
    private var perPage: Int { max(1, Int(viewportWidth / itemStride)) }
    /// 현재 왼쪽 항목의 인덱스 (없으면 맨 앞으로 간주)
    private var currentLeadingIndex: Int {
        guard let id = leadingID,
              let i = history.entries.firstIndex(where: { $0.id == id }) else { return 0 }
        return i
    }
    private var canScrollLeft: Bool { currentLeadingIndex > 0 }
    private var canScrollRight: Bool { currentLeadingIndex + perPage < history.entries.count }

    public var body: some View {
        VStack(spacing: 16) {
            // 인라인 타이틀 — 트래픽 라이트 행 높이만큼(28pt) 상단 영역 확보, 중앙 정렬
            Text("SnapScreen")
                .font(DesignTokens.Typography.windowTitle)
                .frame(maxWidth: .infinity, minHeight: 28)

            HStack(spacing: 10) {
                ForEach(items, id: \.symbol) { item in
                    captureTile(item)
                }
            }

            Divider()

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

            if history.entries.isEmpty {
                Text("아직 캡처가 없습니다")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)
            } else {
                capturesScroller
            }

            footer
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(width: 440)
        .background(
            LinearGradient(colors: [DesignTokens.Colors.homeBackgroundTop,
                                    DesignTokens.Colors.homeBackgroundBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: - 캡처 타일

    @ViewBuilder
    private func captureTile(_ item: Item) -> some View {
        Button { onCapture(item.mode) } label: {
            VStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(DesignTokens.Colors.accentIconTint)
                Text(item.title).font(.system(size: 13, weight: .semibold))
                shortcutView(item.shortcutName)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
        .buttonStyle(CaptureTileButtonStyle())
        .accessibilityLabel(item.title)
        .accessibilityHint("스크린샷을 캡처합니다")
    }

    /// 단축키 표시: 설정돼 있으면 개별 키캡 칩, 미설정이면 "미설정" 텍스트.
    @ViewBuilder
    private func shortcutView(_ name: KeyboardShortcuts.Name) -> some View {
        let keys = ShortcutKeycaps.decompose(KeyboardShortcuts.getShortcut(for: name))
        if keys.isEmpty {
            Text("미설정").font(.system(size: 11)).foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { KeycapChip($0) }
            }
        }
    }

    // MARK: - 최근 캡처

    @ViewBuilder
    private var capturesScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(history.entries) { entry in
                    thumbnail(entry)
                }
            }
            .padding(.vertical, 2)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $leadingID, anchor: .leading)
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { viewportWidth = geo.size.width }
                .onChange(of: geo.size.width) { viewportWidth = geo.size.width }
        })
        .overlay(alignment: .leading) {
            if canScrollLeft { arrow("chevron.left") { scrollBy(-1) } }
        }
        .overlay(alignment: .trailing) {
            if canScrollRight { arrow("chevron.right") { scrollBy(1) } }
        }
        .frame(height: 86)
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }

    /// direction: -1 왼쪽 / +1 오른쪽. 한 뷰포트만큼 이동(leading 항목 id를 바꿔 스크롤).
    private func scrollBy(_ direction: Int) {
        guard !history.entries.isEmpty else { return }
        let target = min(max(currentLeadingIndex + direction * perPage, 0),
                         history.entries.count - 1)
        withAnimation { leadingID = history.entries[target].id }
    }

    @ViewBuilder
    private func thumbnail(_ entry: HistoryEntry) -> some View {
        let image = NSImage(contentsOf: history.thumbnailURL(id: entry.id))
        ZStack(alignment: .topTrailing) {
            Button { onOpenEntry(entry) } label: {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 120, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.thumb))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.thumb)
                    .strokeBorder(DesignTokens.Colors.hairline))
            }
            .buttonStyle(.plain)

            if hoveredID == entry.id {
                Button { history.remove(id: entry.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(DesignTokens.Colors.thumbDeleteButtonBackground))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help("삭제")
            }
        }
        .help(entry.date.formatted(date: .abbreviated, time: .shortened))
        .onHover { hovering in
            if hovering { hoveredID = entry.id }
            else if hoveredID == entry.id { hoveredID = nil }
        }
    }

    // MARK: - 푸터

    private var footer: some View {
        HStack {
            Button { onOpenSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("설정 열기")

            Spacer()

            Text("v\(AppInfo.version)")
                .font(DesignTokens.Typography.mono)
                .foregroundStyle(.tertiary)
        }
    }
}

/// 캡처 타일 버튼 스타일: 토큰 배경 + 내부 상단 하이라이트 + 1px 테두리, hover 시 밝게·press 시 축소.
private struct CaptureTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration)
    }

    private struct TileBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(DesignTokens.Colors.tileFill)
                .overlay(alignment: .top) {
                    // 내부 상단 하이라이트 1px (라운드 클립 안쪽)
                    DesignTokens.Colors.tileTopHighlight.frame(height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.tile))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.tile)
                        .strokeBorder(DesignTokens.Colors.tileBorder, lineWidth: 1)
                )
                .brightness(hovering ? 0.03 : 0)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
```

- [ ] **Step 4: 빌드 & 회귀 테스트**

Run: `swift build`
Expected: `Build complete!` (오류 없음).

Run: `swift test`
Expected: 기존 88개 테스트 전부 PASS (홈 변경이 로직에 영향 없음 확인).

- [ ] **Step 5: 실행 스모크 검증**

Run: `Scripts/run.sh`
Expected: 앱이 크래시 없이 실행되고 홈 창이 뜬다. (터미널/Console에 크래시 로그가 없어야 함.) 홈 창이 뜬 것을 확인한 뒤 앱을 종료(`pkill -f SnapScreen` 또는 창 닫기)한다.

주의: 이 서브에이전트는 화면을 "볼" 수 없으므로, 여기서는 **실행/크래시 여부만** 확인한다. 색·레이아웃·라이트/다크 등 **육안 검증은 컨트롤러/사용자가 별도로 수행**한다(아래 완료 기준 참조).

- [ ] **Step 6: UTF-8 확인**

Run: `file -I Sources/SnapScreenKit/Home/HomeView.swift Sources/SnapScreenKit/Home/HomeWindowController.swift Sources/SnapScreenKit/AppCore/AppDelegate.swift`
Expected: 모두 `charset=utf-8`.

- [ ] **Step 7: Commit**

```bash
git add Sources/SnapScreenKit/Home/HomeWindowController.swift Sources/SnapScreenKit/AppCore/AppDelegate.swift Sources/SnapScreenKit/Home/HomeView.swift
git commit -m "feat: 홈 창 리디자인 (인라인 타이틀바·토큰 기반 캡처 타일·키캡 칩·설정 기어)"
```

---

## Self-Review (스펙 대조)

- 인라인 투명 타이틀바 + 트래픽 라이트 유지 → Task 2 Step 1 ✓
- 폭 440 → HomeView `.frame(width: 440)` ✓
- 캡처 타일 radius 14·패딩 상18/하14·tileFill·tileBorder·상단 하이라이트·26pt accentIconTint 아이콘 → Task 2 Step 3 ✓
- 키캡 칩 + "미설정" 폴백 → `shortcutView` ✓
- hover 밝게 / press scale 0.98 → `CaptureTileButtonStyle` ✓
- 최근 캡처: 썸네일 radius 10·hairline·18pt 삭제버튼(0.55) + 스크롤/화살표/hover 로직 유지 → ✓
- 푸터: 설정 기어(gearshape 15pt tertiary → onOpenSettings) + 버전 mono 10.5pt → `footer` ✓
- DesignTokens 홈 토큰 추가 → Task 1 ✓
- 배선(AppDelegate→WindowController→View) → Task 2 Step 1·2·3 ✓

## 완료 기준

- 파일 4개 수정, `swift build` 성공, `swift test` 88개 통과.
- `Scripts/run.sh` 실행 스모크(크래시 없음, 홈 창 표시).
- **육안 검증(컨트롤러/사용자)**: (1) 라이트/다크 배경·타일·텍스트, (2) 키캡 칩/미설정 폴백, (3) 썸네일·삭제버튼·화살표, (4) 푸터 기어→설정 창 열림, (5) 인라인 타이틀바(트래픽 라이트+중앙 타이틀), (6) 캡처 3종·히스토리 열기 회귀 없음.
- 한글 소스 UTF-8.

## 다음 단계

홈 완료 후 세 번째 하위 프로젝트 **편집기 리디자인**(상단 가로 툴바 → 좌측 레일 + 우측 인스펙터, 신규 상태 `lineWidth`/`shadowEnabled`가 렌더러까지 전파)으로 진행한다.
