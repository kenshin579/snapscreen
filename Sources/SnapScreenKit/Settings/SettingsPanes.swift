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
        SettingsPaneLayout(L("Shortcuts")) {
            SettingsCard {
                recorderRow(L("Area Capture"), name: .captureArea)
                SettingsRowDivider()
                recorderRow(L("Window Capture"), name: .captureWindow)
                SettingsRowDivider()
                recorderRow(L("Full Screen Capture"), name: .captureFullScreen)
            }
            SettingsCaption(L("Click an item to record a new shortcut combination."))
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
        SettingsPaneLayout(L("Saving")) {
            SettingsCard {
                SettingsRow {
                    Text(L("Save Folder")).font(.system(size: 13))
                    Spacer()
                    Text(settings.saveFolderOverride ?? L("Follows system screenshot location"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(L("Change…")) { pickFolder() }
                    if settings.saveFolderOverride != nil {
                        Button(L("Default")) { settings.saveFolderOverride = nil }
                    }
                }
                SettingsRowDivider()
                SettingsRow {
                    Text(L("Filename Prefix")).font(.system(size: 13))
                    Spacer()
                    TextField("snapscreen", text: $settings.filenamePrefix)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
            }
            SettingsCaption(L("If you don't set a save folder, it follows the system screenshot location."))
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
        SettingsPaneLayout(L("History")) {
            SettingsCard {
                SettingsRow {
                    Text(L("Keep Limit")).font(.system(size: 13))
                    Spacer()
                    Picker("", selection: $settings.historyLimit) {
                        ForEach([20, 50, 100, 200], id: \.self) { count in
                            Text(L("\(count) items")).tag(count)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsCaption(L("Sets how many recent captures to keep."))
        }
    }
}

/// 정보 페인 — 버전·업데이트 (기존 로직 동작 무변경 이동).
struct AboutPane: View {
    @ObservedObject var updateState: UpdateState

    var body: some View {
        SettingsPaneLayout(L("About")) {
            SettingsCard {
                SettingsRow {
                    Text(L("Version")).font(.system(size: 13))
                    Spacer()
                    Text(AppInfo.version)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                SettingsRowDivider()
                SettingsRow {
                    updateStatusText
                    Spacer()
                    Button(L("Check for Updates")) {
                        Task { await updateState.check() }
                    }
                    .disabled(updateState.phase == .checking || updateState.phase == .installing)
                    if case .available(let version, let downloadURL) = updateState.phase {
                        Button(L("Upgrade")) {
                            upgrade(version: version, downloadURL: downloadURL)
                        }
                    } else if updateState.phase == .installing {
                        Button(L("Downloading…")) {}.disabled(true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var updateStatusText: some View {
        switch updateState.phase {
        case .idle:
            Text(L("Latest version: unknown")).font(.system(size: 13)).foregroundStyle(.secondary)
        case .checking:
            Text(L("Checking…")).font(.system(size: 13)).foregroundStyle(.secondary)
        case .upToDate:
            Text(L("Up to date ✓")).font(.system(size: 13)).foregroundStyle(.secondary)
        case .available(let version, _):
            Text(L("v\(version) available")).font(.system(size: 13)).fontWeight(.medium)
        case .installing:
            Text(L("Installing…")).font(.system(size: 13)).foregroundStyle(.secondary)
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
                    alert.messageText = L("Update Complete")
                    alert.informativeText = errorMessage
                    alert.addButton(withTitle: L("OK"))
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                } else {
                    updateState.phase = .failed(errorMessage)
                    let alert = NSAlert()
                    alert.messageText = L("Update Failed")
                    alert.informativeText = errorMessage + "\n" + L("You can install manually from the releases page.")
                    alert.addButton(withTitle: L("Open Releases Page"))
                    alert.addButton(withTitle: L("Close"))
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
