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
