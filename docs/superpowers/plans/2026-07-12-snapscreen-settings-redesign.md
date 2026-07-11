# 설정 리디자인 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 설정 창을 grouped Form에서 사이드바 2-pane(190pt 사이드바 + 카드 콘텐츠, 620×430 창, 인라인 투명 타이틀바)으로 재구성한다. 기존 기능·동작은 전부 유지.

**Architecture:** 2개 태스크 — (1) DesignTokens에 설정 고유 색 토큰 추가, (2) 설정 UI 재구성(신규 `SettingsCard`/`SettingsPanes` + `SettingsView` 재작성 + `SettingsWindowController` 인라인 타이틀바). 단축키 recorder는 네이티브 `KeyboardShortcuts.Recorder`를 카드 행에 그대로 배치(녹음 안전 로직 보존). 기존 폴더 선택(NSOpenPanel)·업데이트/업그레이드(NSAlert) 로직은 `SettingsPanes`로 동작 무변경 이동.

**Tech Stack:** Swift, SwiftUI, AppKit(NSWindow/NSOpenPanel/NSAlert), KeyboardShortcuts.

**참고 스펙:** `docs/superpowers/specs/2026-07-12-snapscreen-settings-redesign-design.md`
**디자인 값 출처:** `docs/design/design_handoff_snapscreen_redesign/README.md` §3

---

## File Structure

- **Modify** `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift` (Task 1) — `settingsSidebar`, `settingsCard` 토큰.
- **Create** `Sources/SnapScreenKit/Settings/SettingsCard.swift` (Task 2) — 카드/행/구분선/캡션 공용 컴포넌트.
- **Create** `Sources/SnapScreenKit/Settings/SettingsPanes.swift` (Task 2) — 4개 페인 + 페인 레이아웃(기존 pickFolder/upgrade 로직 이동).
- **Rewrite** `Sources/SnapScreenKit/Settings/SettingsView.swift` (Task 2) — `SettingsSection` enum + 사이드바 + 셸.
- **Modify** `Sources/SnapScreenKit/Settings/SettingsWindowController.swift` (Task 2) — 인라인 타이틀바.

Task 2의 4개 파일은 서로 참조(셸→페인→카드)하므로 한 태스크로 묶는다.

---

## Task 1: DesignTokens 설정 토큰 추가

**Files:**
- Modify: `Sources/SnapScreenKit/DesignSystem/DesignTokens.swift`

- [ ] **Step 1: `DesignTokens.Colors`에 토큰 추가**

`enum Colors` 안, 기존 `thumbDeleteButtonBackground` 정의 다음(닫는 `}` 직전)에 추가:

```swift

        // MARK: 설정 화면 고유
        /// 설정 사이드바 배경 — 라이트 #ECECF0 90% / 다크 #1C1C1F 90%
        public static let settingsSidebar = dynamic(
            light: NSColor(hex: 0xECECF0, alpha: 0.9),
            dark: NSColor(hex: 0x1C1C1F, alpha: 0.9))
        /// 설정 grouped 카드 배경 — 라이트 흰색 / 다크 흰색 5.5%
        public static let settingsCard = dynamic(
            light: .white,
            dark: NSColor(white: 1, alpha: 0.055))
```

- [ ] **Step 2: 빌드 검증**

Run: `swift build`
Expected: `Build complete!` (기존 `NSColor(hex:alpha:)`의 `alpha` 파라미터 사용 — 이미 정의돼 있음).

- [ ] **Step 3: UTF-8 & Commit**

Run: `file -I Sources/SnapScreenKit/DesignSystem/DesignTokens.swift` → utf-8.
```bash
git add Sources/SnapScreenKit/DesignSystem/DesignTokens.swift
git commit -m "feat: 설정 화면 고유 디자인 토큰(사이드바·카드 배경) 추가"
```

---

## Task 2: 설정 UI 재구성 (카드 + 페인 + 셸 + 창)

**Files:**
- Create: `Sources/SnapScreenKit/Settings/SettingsCard.swift`
- Create: `Sources/SnapScreenKit/Settings/SettingsPanes.swift`
- Rewrite: `Sources/SnapScreenKit/Settings/SettingsView.swift`
- Modify: `Sources/SnapScreenKit/Settings/SettingsWindowController.swift`

- [ ] **Step 1: `SettingsCard.swift` 생성**

```swift
import SwiftUI

/// 설정 콘텐츠의 grouped 카드. 행(`SettingsRow`)들을 세로로 담고
/// 행 사이에는 호출부가 `SettingsRowDivider`를 끼워 넣는다.
struct SettingsCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DesignTokens.Colors.settingsCard)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(DesignTokens.Colors.hairline, lineWidth: 1))
    }
}

/// 카드 안 한 행. 패딩 11×13, 좌측 정렬 HStack.
struct SettingsRow<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 행 사이 hairline (좌측 인셋 13).
struct SettingsRowDivider: View {
    var body: some View {
        DesignTokens.Colors.hairline
            .frame(height: 1)
            .padding(.leading, 13)
    }
}

/// 카드 아래 도움말 캡션.
struct SettingsCaption: View {
    private let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}
```

- [ ] **Step 2: `SettingsPanes.swift` 생성** (기존 SettingsView의 pickFolder/updateStatusText/upgrade 로직을 동작 무변경으로 이동)

```swift
import SwiftUI
import AppKit
import KeyboardShortcuts

/// 페인 공통 레이아웃: 페이지 타이틀 + 카드들, 상단 정렬.
struct SettingsPaneLayout<Content: View>: View {
    private let title: String
    private let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(DesignTokens.Typography.pageTitle)
            content
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 단축키 페인 — 네이티브 Recorder를 카드 행에 배치 (녹음 안전 로직 보존).
struct ShortcutsPane: View {
    var body: some View {
        SettingsPaneLayout("단축키") {
            SettingsCard {
                recorderRow("영역 캡처", name: .captureArea)
                SettingsRowDivider()
                recorderRow("창 캡처", name: .captureWindow)
                SettingsRowDivider()
                recorderRow("전체 화면 캡처", name: .captureFullScreen)
            }
            SettingsCaption("항목을 클릭해 새 단축키 조합을 녹음할 수 있습니다.")
        }
    }

    private func recorderRow(_ label: String, name: KeyboardShortcuts.Name) -> some View {
        SettingsRow {
            Text(label).font(.system(size: 13))
            Spacer()
            KeyboardShortcuts.Recorder("", name: name)
        }
    }
}

/// 저장 페인 — 저장 폴더·파일명 접두어.
struct SavingPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsPaneLayout("저장") {
            SettingsCard {
                SettingsRow {
                    Text("저장 폴더").font(.system(size: 13))
                    Spacer()
                    Text(settings.saveFolderOverride ?? "시스템 스크린샷 위치 따름")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("변경…") { pickFolder() }
                    if settings.saveFolderOverride != nil {
                        Button("기본값") { settings.saveFolderOverride = nil }
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    Text("파일명 접두어").font(.system(size: 13))
                    Spacer()
                    TextField("snapscreen", text: $settings.filenamePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
            SettingsCaption("저장 폴더를 지정하지 않으면 시스템 스크린샷 위치를 따릅니다.")
        }
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

/// 히스토리 페인 — 보관 개수.
struct HistoryPane: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsPaneLayout("히스토리") {
            SettingsCard {
                SettingsRow {
                    Text("보관 개수").font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $settings.historyLimit) {
                        ForEach([20, 50, 100, 200], id: \.self) { Text("\($0)개").tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsCaption("최근 캡처를 최대 몇 개까지 보관할지 정합니다.")
        }
    }
}

/// 정보 페인 — 버전·업데이트 (기존 로직 동작 무변경 이동).
struct AboutPane: View {
    @ObservedObject var updateState: UpdateState

    var body: some View {
        SettingsPaneLayout("정보") {
            SettingsCard {
                SettingsRow {
                    Text("버전").font(.system(size: 13))
                    Spacer()
                    Text(AppInfo.version)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                SettingsRowDivider()
                SettingsRow {
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
        }
    }

    @ViewBuilder
    private var updateStatusText: some View {
        switch updateState.phase {
        case .idle:
            Text("최신 버전: 미확인").font(.system(size: 13)).foregroundStyle(.secondary)
        case .checking:
            Text("확인 중…").font(.system(size: 13)).foregroundStyle(.secondary)
        case .upToDate:
            Text("최신 버전입니다 ✓").font(.system(size: 13)).foregroundStyle(.secondary)
        case .available(let version, _):
            Text("v\(version) 사용 가능").font(.system(size: 13)).fontWeight(.medium)
        case .installing:
            Text("설치 중…").font(.system(size: 13)).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.system(size: 13)).foregroundStyle(.red)
        }
    }

    private func upgrade(version: String, downloadURL: URL) {
        updateState.phase = .installing
        Task {
            if let errorMessage = await UpdateInstaller.install(version: version,
                                                                downloadURL: downloadURL) {
                if errorMessage == UpdateInstaller.relaunchFailedMessage {
                    updateState.phase = .idle
                    let alert = NSAlert()
                    alert.messageText = "업데이트 완료"
                    alert.informativeText = errorMessage
                    alert.addButton(withTitle: "확인")
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                } else {
                    updateState.phase = .failed(errorMessage)
                    let alert = NSAlert()
                    alert.messageText = "업데이트 실패"
                    alert.informativeText = errorMessage + "\n릴리스 페이지에서 수동으로 설치할 수 있습니다."
                    alert.addButton(withTitle: "릴리스 페이지 열기")
                    alert.addButton(withTitle: "닫기")
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
                    }
                }
            }
            // 성공 시 앱이 종료·재실행되므로 후속 코드 없음
        }
    }
}
```

- [ ] **Step 3: `SettingsView.swift` 전체 교체**

```swift
import SwiftUI
import AppKit

/// 설정 섹션 (사이드바 네비게이션).
enum SettingsSection: CaseIterable {
    case shortcuts, saving, history, about

    var label: String {
        switch self {
        case .shortcuts: return "단축키"
        case .saving: return "저장"
        case .history: return "히스토리"
        case .about: return "정보"
        }
    }

    var symbol: String {
        switch self {
        case .shortcuts: return "keyboard"
        case .saving: return "folder.fill"
        case .history: return "clock.fill"
        case .about: return "info.circle"
        }
    }

    var iconTileColor: Color {
        switch self {
        case .shortcuts: return Color(nsColor: NSColor(hex: 0x007AFF))
        case .saving: return Color(nsColor: NSColor(hex: 0x34C759))
        case .history: return Color(nsColor: NSColor(hex: 0x8E8E93))
        case .about: return DesignTokens.dynamic(light: NSColor(hex: 0x636366),
                                                 dark: NSColor(hex: 0x48484A))
        }
    }
}

/// 설정 창 내용: 사이드바 2-pane (190pt 사이드바 + 카드 기반 콘텐츠).
public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateState: UpdateState
    @State private var section: SettingsSection = .shortcuts
    @State private var hovered: SettingsSection?

    public init(settings: SettingsStore, updateState: UpdateState) {
        self.settings = settings
        self.updateState = updateState
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch section {
                case .shortcuts: ShortcutsPane()
                case .saving: SavingPane(settings: settings)
                case .history: HistoryPane(settings: settings)
                case .about: AboutPane(updateState: updateState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 620, height: 430)
    }

    // MARK: - 사이드바

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Spacer().frame(height: 40) // 트래픽 라이트 영역
            ForEach(SettingsSection.allCases, id: \.self) { s in
                sidebarRow(s)
            }
            Spacer()
            Text("v\(AppInfo.version)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.leading, 9)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .frame(width: 190)
        .frame(maxHeight: .infinity)
        .background(DesignTokens.Colors.settingsSidebar)
        .overlay(alignment: .trailing) { DesignTokens.Colors.hairline.frame(width: 1) }
    }

    private func sidebarRow(_ s: SettingsSection) -> some View {
        Button { section = s } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.iconTile)
                    .fill(s.iconTileColor)
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: s.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.white))
                Text(s.label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(section == s ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sidebarRow)
                .fill(section == s ? Color.accentColor
                      : (hovered == s ? Color.primary.opacity(0.06) : Color.clear)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = s }
            else if hovered == s { hovered = nil }
        }
    }
}
```

- [ ] **Step 4: `SettingsWindowController.swift` — 인라인 타이틀바**

`init`의 window 설정부에서:
```swift
        window.styleMask = [.titled, .closable]
```
을 다음으로 교체:
```swift
        // 인라인 타이틀바 — 트래픽 라이트가 사이드바 위에 얹힌다 (System Settings 스타일)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
```
(`window.title = "SnapScreen 설정"`은 유지 — Mission Control/VoiceOver용, 화면 표시는 숨김. 나머지 코드 무변경.)

- [ ] **Step 5: 빌드 & 테스트 & 스모크**

Run: `swift build` → 성공.
Run: `swift test` → 88개 통과 (설정은 UI라 신규 테스트 없음).
Run: `Scripts/run.sh` → 크래시 없이 실행 확인 후 `pkill -f "build/SnapScreen.app"`. (설정 창 자체의 육안 검증은 컨트롤러/사용자가 수행.)

- [ ] **Step 6: UTF-8 & Commit**

`file -I` 4개 파일 → 모두 utf-8.
```bash
git add Sources/SnapScreenKit/Settings/SettingsCard.swift Sources/SnapScreenKit/Settings/SettingsPanes.swift Sources/SnapScreenKit/Settings/SettingsView.swift Sources/SnapScreenKit/Settings/SettingsWindowController.swift
git commit -m "feat: 설정 창 사이드바 2-pane 리디자인 (카드 콘텐츠·인라인 타이틀바·네이티브 recorder 유지)"
```

---

## Self-Review (스펙 대조)

- `SettingsSection` enum 4케이스 + 라벨/심볼/아이콘 타일 색(정보만 동적) → Task 2 Step 3 ✓
- 사이드바 190pt·사이드 재질 토큰·행 패딩 7×9·radius 8·아이콘 타일 22pt·라벨 12.5pt·선택 액센트+흰글자·hover·하단 버전 → Step 3 ✓
- 카드 radius 12·라이트 흰/다크 5.5%·행 패딩 11×13·hairline 좌인셋 13·캡션 11.5pt → Step 1 (SettingsCard) ✓
- 페이지 타이틀 15pt bold·페인 패딩 → SettingsPaneLayout ✓
- recorder 네이티브 유지 (라벨 13pt + Recorder) → ShortcutsPane ✓
- 저장/히스토리/정보 기존 기능 무변경 이동 (pickFolder/updateStatusText/upgrade 원본 그대로) → Step 2 ✓
- 인라인 타이틀바 + 기존 policyManager/타이틀 유지 → Step 4 ✓
- 토큰 신설 settingsSidebar/settingsCard → Task 1 ✓

타입 일관성: `SettingsCard`/`SettingsRow`/`SettingsRowDivider`/`SettingsCaption`/`SettingsPaneLayout` 이름이 Step 1↔2 일치. `DesignTokens.dynamic`은 internal(동일 모듈 접근 가능). `NSColor(hex:alpha:)` 기존재.

## 완료 기준

- 파일 5개 수정/신설, `swift build`/`swift test`(88개) 통과, 실행 스모크.
- **육안 검증(사용자)**: 사이드바 4항목 전환·선택/hover 상태, recorder 재녹음(오발동 방지·시스템 예약 검사), 폴더 변경/기본값, 접두어 입력, 보관 개수, 업데이트 확인, 라이트/다크, 인라인 타이틀바(트래픽 라이트가 사이드바 위).
- 한글 소스 UTF-8.

## 다음 단계

리디자인 4부작 완결. 이후 후보: 다국어 지원(보류), `docs/manual-test-checklist.md` 갱신, 릴리스 태깅.
