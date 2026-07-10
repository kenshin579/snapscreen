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
    // 현재 왼쪽(leading)에 정렬된 항목 id. 트랙패드·화살표 스크롤 모두 반영(.scrollPosition).
    @State private var leadingID: UUID?
    @State private var hoveredID: UUID?
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
                capturesScroller
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12)))
            }
            .buttonStyle(.plain)

            if hoveredID == entry.id {
                Button { history.remove(id: entry.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.6)))
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
}
