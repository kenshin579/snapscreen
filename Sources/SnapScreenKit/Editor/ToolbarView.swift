import SwiftUI

@MainActor
public struct ToolbarView: View {
    @ObservedObject var state: EditorState
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    public init(state: EditorState, onUndo: @escaping () -> Void, onRedo: @escaping () -> Void,
                onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.state = state
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onCopy = onCopy
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: $state.tool) {
                ForEach(EditorTool.allCases) { tool in
                    Image(systemName: tool.symbolName)
                        .help(tool.label)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Divider().frame(height: 20)

            HStack(spacing: 6) {
                ForEach(PaletteColor.allCases, id: \.self) { color in
                    Circle()
                        .fill(Color(nsColor: color.nsColor))
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(
                            state.color == color ? Color.accentColor : Color.gray.opacity(0.4),
                            lineWidth: state.color == color ? 2 : 1))
                        .onTapGesture { state.color = color }
                }
            }

            Divider().frame(height: 20)

            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .help("실행 취소 (⌘Z)")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                .help("실행 복귀 (⇧⌘Z)")

            Spacer()

            Button(action: onCopy) { Label("복사", systemImage: "doc.on.doc") }
                .help("클립보드로 복사 (⌘C)")
            Button(action: onSave) { Label("저장", systemImage: "square.and.arrow.down") }
                .help("파일로 저장 (⌘S)")
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }
}
