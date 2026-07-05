import SwiftUI
import KeyboardShortcuts

public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateState: UpdateState

    public init(settings: SettingsStore, updateState: UpdateState) {
        self.settings = settings
        self.updateState = updateState
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
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

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
                if errorMessage == UpdateInstaller.relaunchFailedMessage {
                    updateState.phase = .idle
                    let alert = NSAlert()
                    alert.messageText = "업데이트 완료"
                    alert.informativeText = errorMessage
                    alert.addButton(withTitle: "확인")
                    alert.runModal()
                } else {
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
            }
            // 성공 시 앱이 종료·재실행되므로 후속 코드 없음
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
