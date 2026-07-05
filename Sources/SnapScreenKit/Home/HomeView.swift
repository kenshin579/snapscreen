import SwiftUI
import KeyboardShortcuts

/// 홈 창 내용: 캡처 버튼 3개(단축키 병기) + 하단 버전.
/// 버튼은 주입된 onCapture 클로저로 CaptureCoordinator.beginCapture를 호출한다.
public struct HomeView: View {
    let onCapture: @MainActor (CaptureMode) -> Void

    public init(onCapture: @escaping @MainActor (CaptureMode) -> Void) {
        self.onCapture = onCapture
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

    public var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 12) {
                ForEach(items, id: \.symbol) { item in
                    Button {
                        onCapture(item.mode)
                    } label: {
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
}
