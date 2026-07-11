import SwiftUI
import KeyboardShortcuts

/// 홈 창 내용: 인라인 타이틀 + 캡처 타일 3개 + 최근 캡처 그리드 + 푸터(설정 기어/버전).
public struct HomeView: View {
    let onCapture: @MainActor (CaptureMode) -> Void
    @ObservedObject var history: HistoryStore
    let onOpenEntry: @MainActor (HistoryEntry) -> Void
    let onOpenSettings: @MainActor () -> Void

    public init(onCapture: @escaping @MainActor (CaptureMode) -> Void,
                history: HistoryStore,
                onOpenEntry: @escaping @MainActor (HistoryEntry) -> Void,
                onOpenSettings: @escaping @MainActor () -> Void) {
        self.onCapture = onCapture
        self.history = history
        self.onOpenEntry = onOpenEntry
        self.onOpenSettings = onOpenSettings
    }

    private struct Item {
        let mode: CaptureMode
        let symbol: String
        let title: String
        let shortcutName: KeyboardShortcuts.Name
    }
    private let items: [Item] = [
        Item(mode: .area, symbol: "rectangle.dashed", title: L("Area"), shortcutName: .captureArea),
        Item(mode: .window, symbol: "macwindow", title: L("Window"), shortcutName: .captureWindow),
        Item(mode: .fullScreen, symbol: "display", title: L("Full Screen"), shortcutName: .captureFullScreen)
    ]
    // 현재 왼쪽(leading)에 정렬된 항목 id. 트랙패드·화살표 스크롤 모두 반영(.scrollPosition).
    @State private var leadingID: UUID?
    @State private var hoveredID: UUID?
    @State private var showClearConfirm = false
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
        VStack(spacing: 16) {
            // 인라인 타이틀 — 트래픽 라이트 행 높이만큼(28pt) 상단 영역 확보, 중앙 정렬
            Text("SnapScreen")
                .font(DesignTokens.Typography.windowTitle)
                .frame(maxWidth: .infinity, minHeight: 28)

            HStack(spacing: 10) {
                ForEach(items, id: \.symbol) { item in
                    captureTile(item)
                }
            }

            Divider()

            HStack {
                Text(L("Recent Captures")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !history.entries.isEmpty {
                    Button(L("Clear All")) { showClearConfirm = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .confirmationDialog(L("Clear all recent captures?"),
                                isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button(L("Clear All"), role: .destructive) { history.clear() }
                Button(L("Cancel"), role: .cancel) {}
            }

            if history.entries.isEmpty {
                Text(L("No captures yet"))
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, minHeight: 78, maxHeight: 78)
            } else {
                capturesScroller
            }

            footer
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(width: 440)
        .background(
            LinearGradient(colors: [DesignTokens.Colors.homeBackgroundTop,
                                    DesignTokens.Colors.homeBackgroundBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
    }

    // MARK: - 캡처 타일

    @ViewBuilder
    private func captureTile(_ item: Item) -> some View {
        Button { onCapture(item.mode) } label: {
            VStack(spacing: 8) {
                Image(systemName: item.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(DesignTokens.Colors.accentIconTint)
                Text(item.title).font(.system(size: 13, weight: .semibold))
                shortcutView(item.shortcutName)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18)
            .padding(.bottom, 14)
        }
        .buttonStyle(CaptureTileButtonStyle())
        .accessibilityLabel(item.title)
        .accessibilityHint(L("Captures a screenshot"))
    }

    /// 단축키 표시: 설정돼 있으면 개별 키캡 칩, 미설정이면 "미설정" 텍스트.
    @ViewBuilder
    private func shortcutView(_ name: KeyboardShortcuts.Name) -> some View {
        let keys = ShortcutKeycaps.decompose(KeyboardShortcuts.getShortcut(for: name))
        if keys.isEmpty {
            Text(L("Not Set")).font(.system(size: 11)).foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 3) {
                ForEach(keys, id: \.self) { KeycapChip($0) }
            }
        }
    }

    // MARK: - 최근 캡처

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
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.thumb))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.thumb)
                    .strokeBorder(DesignTokens.Colors.hairline))
            }
            .buttonStyle(.plain)

            if hoveredID == entry.id {
                Button { history.remove(id: entry.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(DesignTokens.Colors.thumbDeleteButtonBackground))
                }
                .buttonStyle(.plain)
                .padding(4)
                .help(L("Delete"))
            }
        }
        .help(entry.date.formatted(date: .abbreviated, time: .shortened))
        .onHover { hovering in
            if hovering { hoveredID = entry.id }
            else if hoveredID == entry.id { hoveredID = nil }
        }
    }

    // MARK: - 푸터

    private var footer: some View {
        HStack {
            Button { onOpenSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help(L("Open Settings"))

            Spacer()

            Text("v\(AppInfo.version)")
                .font(DesignTokens.Typography.mono)
                .foregroundStyle(.tertiary)
        }
    }
}

/// 캡처 타일 버튼 스타일: 토큰 배경 + 내부 상단 하이라이트 + 1px 테두리, hover 시 밝게·press 시 축소.
private struct CaptureTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration)
    }

    private struct TileBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(DesignTokens.Colors.tileFill)
                .overlay(alignment: .top) {
                    // 내부 상단 하이라이트 1px (라운드 클립 안쪽)
                    DesignTokens.Colors.tileTopHighlight.frame(height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.tile))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.tile)
                        .strokeBorder(DesignTokens.Colors.tileBorder, lineWidth: 1)
                )
                .brightness(hovering ? 0.03 : 0)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
