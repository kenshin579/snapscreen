import AppKit
import SwiftUI

@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let result: CaptureResult
    private let settings: SettingsStore
    private let store = AnnotationStore()
    private let state = EditorState()
    private var canvas: CanvasView!
    private var onClose: (() -> Void)?

    public init(result: CaptureResult, settings: SettingsStore, onClose: (() -> Void)? = nil) {
        self.result = result
        self.settings = settings
        self.onClose = onClose

        let pointSize = CGSize(width: CGFloat(result.image.width) / result.scale,
                               height: CGFloat(result.image.height) / result.scale)
        let maxSize = NSScreen.main.map { CGSize(width: $0.visibleFrame.width * 0.8,
                                                 height: $0.visibleFrame.height * 0.8) }
            ?? CGSize(width: 1200, height: 800)
        let fit = min(1, maxSize.width / pointSize.width, maxSize.height / pointSize.height)
        let contentSize = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "SnapScreen"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let toolbarHeight: CGFloat = 44
        window.setContentSize(CGSize(width: contentSize.width,
                                     height: contentSize.height + toolbarHeight))
        window.contentAspectRatio = .zero // 툴바 포함이라 비율 고정 해제

        canvas = CanvasView(image: result.image, captureScale: result.scale,
                            store: store, state: state)
        let toolbar = NSHostingView(rootView: ToolbarView(
            state: state,
            onUndo: { [weak self] in self?.undoAction(nil) },
            onRedo: { [weak self] in self?.redoAction(nil) },
            onCopy: { [weak self] in self?.copyMerged(nil) },
            onSave: { [weak self] in self?.saveImage(nil) }
        ))

        let container = NSView()
        container.addSubview(toolbar)
        container.addSubview(canvas)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        canvas.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: toolbarHeight),
            canvas.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            canvas.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        window.contentView = container

        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    required init?(coder: NSCoder) { fatalError() }

    public func windowWillClose(_ notification: Notification) {
        onClose?() // 스펙: 닫으면 경고 없이 폐기
        onClose = nil
    }

    private func flattened() -> CGImage? {
        FlattenRenderer.flatten(image: result.image, annotations: store.annotations, scale: result.scale)
    }

    // MARK: - 메인 메뉴 액션 (MainMenuBuilder의 nil-target 셀렉터가 응답 체인으로 도달)

    @objc public func copyMerged(_ sender: Any?) {
        guard let image = flattened() else { return }
        ClipboardWriter.write(image, scale: result.scale)
    }

    @objc public func saveImage(_ sender: Any?) {
        guard let image = flattened() else { return }
        switch FileSaver(settings: settings).save(image, scale: result.scale) {
        case .saved, .savedToFallback:
            window?.close()
        case .failed(let error):
            Notifier.alertFailure(title: "저장 실패", body: error.localizedDescription)
        }
    }

    @objc public func undoAction(_ sender: Any?) {
        store.undo()
        canvas.needsDisplay = true
    }

    @objc public func redoAction(_ sender: Any?) {
        store.redo()
        canvas.needsDisplay = true
    }
}
