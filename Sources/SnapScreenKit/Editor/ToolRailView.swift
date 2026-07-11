import SwiftUI

/// 편집기 좌측 세로 도구 레일 (폭 52). 9개 주석 도구 + 하단 자르기/텍스트 추출.
@MainActor
public struct ToolRailView: View {
    @ObservedObject var state: EditorState
    @ObservedObject var store: AnnotationStore
    let onCrop: () -> Void
    let onOCR: () -> Void

    public init(state: EditorState, store: AnnotationStore,
                onCrop: @escaping () -> Void, onOCR: @escaping () -> Void) {
        self.state = state
        self.store = store
        self.onCrop = onCrop
        self.onOCR = onOCR
    }

    public var body: some View {
        VStack(spacing: 4) {
            ForEach(EditorTool.allCases) { tool in
                railButton(symbol: tool.symbolName, help: tool.label,
                           selected: state.tool == tool) { state.tool = tool }
            }
            Spacer()
            railButton(symbol: "crop",
                       help: store.annotations.isEmpty ? "자르기 (C)" : "주석을 모두 삭제한 후 자를 수 있습니다",
                       selected: false, disabled: !store.annotations.isEmpty, action: onCrop)
            railButton(symbol: "text.viewfinder", help: "텍스트 추출 (E)",
                       selected: false, action: onOCR)
        }
        .padding(.vertical, 10)
        .frame(width: 52)
        .frame(maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) { DesignTokens.Colors.hairline.frame(width: 1) }
    }

    private func railButton(symbol: String, help: String, selected: Bool,
                            disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(width: 36, height: 32)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.tool)
                    .fill(selected ? Color.accentColor : Color.clear))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(help)
    }
}
