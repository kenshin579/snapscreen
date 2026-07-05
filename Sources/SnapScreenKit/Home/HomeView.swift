import SwiftUI

/// 홈 창 내용: 캡처 버튼 3개(단축키 병기) + 하단 버전.
/// 버튼은 주입된 onCapture 클로저로 CaptureCoordinator.beginCapture를 호출한다.
public struct HomeView: View {
    let onCapture: (CaptureMode) -> Void

    public init(onCapture: @escaping (CaptureMode) -> Void) {
        self.onCapture = onCapture
    }

    private struct Item {
        let mode: CaptureMode
        let symbol: String
        let title: String
        let shortcut: String
    }

    private let items: [Item] = [
        Item(mode: .area, symbol: "rectangle.dashed", title: "영역", shortcut: "⌘⇧1"),
        Item(mode: .window, symbol: "macwindow", title: "창", shortcut: "⌘⇧2"),
        Item(mode: .fullScreen, symbol: "display", title: "전체 화면", shortcut: "⌘⇧0")
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
                            Text(item.shortcut)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12)))
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
