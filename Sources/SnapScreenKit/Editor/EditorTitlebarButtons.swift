import SwiftUI

/// 편집기 타이틀바 우측 접근성 뷰: undo/redo/복사/저장.
@MainActor
public struct EditorTitlebarButtons: View {
    @ObservedObject var store: AnnotationStore
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    public init(store: AnnotationStore,
                onUndo: @escaping () -> Void, onRedo: @escaping () -> Void,
                onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.store = store
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onCopy = onCopy
        self.onSave = onSave
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }
                .buttonStyle(.plain)
                .disabled(!store.canUndo).opacity(store.canUndo ? 1 : 0.35)
                .help(L("Undo (⌘Z)"))
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }
                .buttonStyle(.plain)
                .disabled(!store.canRedo).opacity(store.canRedo ? 1 : 0.35)
                .help(L("Redo (⇧⌘Z)"))
            Button(action: onCopy) { Text(L("Copy")).font(.system(size: 12)) }
                .help(L("Copy to Clipboard (⌘C)"))
            Button(action: onSave) { Text(L("Save")).font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.borderedProminent)
                .help(L("Save to File (⌘S)"))
        }
        .padding(.horizontal, 12)
    }
}
