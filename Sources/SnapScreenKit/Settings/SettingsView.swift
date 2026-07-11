import SwiftUI
import AppKit

/// 설정 섹션 (사이드바 네비게이션).
enum SettingsSection: CaseIterable {
    case shortcuts, saving, history, about

    var label: String {
        switch self {
        case .shortcuts: return L("Shortcuts")
        case .saving: return L("Saving")
        case .history: return L("History")
        case .about: return L("About")
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

/// 선택된 설정 섹션 — 창 컨트롤러가 소유해 외부에서 특정 섹션으로 열 수 있게 한다
/// (예: 메뉴바 "Update available…" 클릭 → About 직행).
final class SettingsUIState: ObservableObject {
    @Published var section: SettingsSection = .shortcuts
}

/// 설정 창 내용: 사이드바 2-pane (190pt 사이드바 + 카드 기반 콘텐츠).
public struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var updateState: UpdateState
    @ObservedObject var ui: SettingsUIState
    @State private var hovered: SettingsSection?

    init(settings: SettingsStore, updateState: UpdateState, ui: SettingsUIState) {
        self.settings = settings
        self.updateState = updateState
        self.ui = ui
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar

            Group {
                switch ui.section {
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
        Button { ui.section = s } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.iconTile)
                    .fill(s.iconTileColor)
                    .frame(width: 22, height: 22)
                    .overlay(Image(systemName: s.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.white))
                Text(s.label)
                    .font(.system(size: 12.5))
                    .foregroundStyle(ui.section == s ? Color.white : Color.primary)
                Spacer()
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sidebarRow)
                .fill(ui.section == s ? Color.accentColor
                      : (hovered == s ? Color.primary.opacity(0.06) : Color.clear)))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hovered = s }
            else if hovered == s { hovered = nil }
        }
    }
}
