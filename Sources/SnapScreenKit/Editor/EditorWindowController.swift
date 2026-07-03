import AppKit

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
        window.contentAspectRatio = pointSize
        super.init(window: window)

        canvas = CanvasView(image: result.image, captureScale: result.scale,
                            store: store, state: state)
        window.contentView = canvas
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
        FlattenRenderer.flatten(image: result.image, annotations: store.annotations)
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
