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
                    .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(history.entries) { entry in
                            thumbnail(entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: 86)
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
            .frame(width: 120, height: 78)
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
