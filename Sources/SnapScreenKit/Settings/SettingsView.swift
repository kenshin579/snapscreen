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
