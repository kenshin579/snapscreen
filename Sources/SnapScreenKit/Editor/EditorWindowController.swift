import AppKit
import Combine
import SwiftUI

@MainActor
public final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let result: CaptureResult
    private var image: CGImage
    private let settings: SettingsStore
    private let store = AnnotationStore()
    private let state = EditorState()
    private var canvas: CanvasView!
    private var onClose: (() -> Void)?
    private let policyManager: ActivationPolicyManager?
    private var toolCancellable: AnyCancellable?
    private var isRecognizing = false
    /// 히스토리에서 연 경우 원본 항목 id — 같은 항목의 중복 창 방지(코디네이터가 조회). 새 캡처는 nil.
    public let historyEntryID: UUID?

    private let railWidth: CGFloat = 52
    private let inspectorWidth: CGFloat = 170

    public init(result: CaptureResult, settings: SettingsStore,
                policyManager: ActivationPolicyManager? = nil,
                historyEntryID: UUID? = nil,
                onClose: (() -> Void)? = nil) {
        self.result = result
        self.image = result.image
        self.settings = settings
        self.policyManager = policyManager
        self.historyEntryID = historyEntryID
        self.onClose = onClose

        let pointSize = CGSize(width: CGFloat(result.image.width) / result.scale,
                               height: CGFloat(result.image.height) / result.scale)
        let maxSize = NSScreen.main.map { CGSize(width: $0.visibleFrame.width * 0.8,
                                                 height: $0.visibleFrame.height * 0.8) }
            ?? CGSize(width: 1200, height: 800)
        let chrome = railWidth + inspectorWidth
        let fit = min(1, (maxSize.width - chrome) / pointSize.width, maxSize.height / pointSize.height)
        let canvasSize = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: canvasSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        // 예정 파일명 (열릴 때 1회 생성) — 중앙 타이틀
        window.title = FilenameFormatter(prefix: settings.filenamePrefix.isEmpty ? "snapscreen"
                                         : settings.filenamePrefix).filename(for: Date())
        window.isReleasedWhenClosed = false
        super.init(window: window)

        // 콘텐츠 하한: 좁은/얇은 캡처도 레일(약 412pt)·최소 캔버스가 잘리지 않게 (캔버스는 레터박스 처리됨)
        window.setContentSize(CGSize(width: max(canvasSize.width, 240) + chrome,
                                     height: max(canvasSize.height, 420)))
        window.contentAspectRatio = .zero
        // 높이 하한: 도구 레일 최소 콘텐츠(약 412pt) + 타이틀바 여유 — 레일 버튼 잘림 방지
        window.minSize = NSSize(width: chrome + 240, height: 460)

        canvas = CanvasView(image: self.image, captureScale: result.scale,
                            store: store, state: state)
        canvas.onCropConfirmed = { [weak self] rect in self?.applyCrop(rect) }
        canvas.onRequestOCR = { [weak self] in self?.performOCR() }

        let rail = NSHostingView(rootView: ToolRailView(
            state: state, store: store,
            onCrop: { [weak self] in self?.canvas.beginCrop() },
            onOCR: { [weak self] in self?.performOCR() }))
        let inspector = NSHostingView(rootView: InspectorView(
            state: state,
            onCrop: { [weak self] in self?.canvas.beginCrop() },
            onOCR: { [weak self] in self?.performOCR() }))

        let container = NSView()
        for v in [rail, canvas!, inspector] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rail.topAnchor.constraint(equalTo: container.topAnchor),
            rail.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: railWidth),

            canvas.leadingAnchor.constraint(equalTo: rail.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: container.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            inspector.leadingAnchor.constraint(equalTo: canvas.trailingAnchor),
            inspector.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: container.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            inspector.widthAnchor.constraint(equalToConstant: inspectorWidth)
        ])
        window.contentView = container

        // 타이틀바 우측 버튼 (undo/redo/복사/저장)
        let titleButtons = NSHostingView(rootView: EditorTitlebarButtons(
            store: store,
            onUndo: { [weak self] in self?.undoAction(nil) },
            onRedo: { [weak self] in self?.redoAction(nil) },
            onCopy: { [weak self] in self?.copyMerged(nil) },
            onSave: { [weak self] in self?.saveImage(nil) }))
        titleButtons.layoutSubtreeIfNeeded()   // 창 부착 전 fittingSize 신뢰성 확보
        titleButtons.frame.size = titleButtons.fittingSize
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = titleButtons
        accessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(accessory)

        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        policyManager?.register(window)
        NSApp.activate(ignoringOtherApps: true)

        // 도구 전환 시 진행 중 crop/erase 자동 취소 (기존 유지)
        toolCancellable = state.$tool.sink { [weak self] _ in
            self?.canvas.cancelCropIfActive()
            self?.canvas.cancelEraseIfActive()
            self?.canvas.needsDisplay = true
            if let canvas = self?.canvas { canvas.window?.invalidateCursorRects(for: canvas) }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    public func windowWillClose(_ notification: Notification) {
        if let window { policyManager?.unregister(window) }
        onClose?()
        onClose = nil
    }

    private func flattened() -> CGImage? {
        FlattenRenderer.flatten(image: image, annotations: store.annotations, scale: result.scale)
    }

    private func applyCrop(_ rect: CGRect) {
        guard let cropped = ImageCropper.crop(image, toBottomLeftRect: rect) else { return }
        image = cropped
        canvas.replaceImage(cropped)
        resizeWindowToImage()
    }

    /// 현재 이미지 비율에 맞게 창 content 크기 재조정 (init 사이징 규칙과 동일, 레일+인스펙터 폭 포함)
    private func resizeWindowToImage() {
        guard let window else { return }
        let pointSize = CGSize(width: CGFloat(image.width) / result.scale,
                               height: CGFloat(image.height) / result.scale)
        let maxSize = NSScreen.main.map { CGSize(width: $0.visibleFrame.width * 0.8,
                                                 height: $0.visibleFrame.height * 0.8) }
            ?? CGSize(width: 1200, height: 800)
        let chrome = railWidth + inspectorWidth
        let fit = min(1, (maxSize.width - chrome) / pointSize.width, maxSize.height / pointSize.height)
        let canvasSize = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)
        window.setContentSize(CGSize(width: max(canvasSize.width, 240) + chrome,
                                     height: max(canvasSize.height, 420)))
    }

    // MARK: - 메인 메뉴 액션 (MainMenuBuilder의 nil-target 셀렉터가 응답 체인으로 도달)

    @objc public func copyMerged(_ sender: Any?) {
        guard let image = flattened() else { return }
        if ClipboardWriter.write(image, scale: result.scale) {
            canvas.showToast("이미지를 복사했습니다")
        }
    }

    @objc public func saveImage(_ sender: Any?) {
        guard let image = flattened() else { return }
        switch FileSaver(settings: settings).save(image, scale: result.scale) {
        case .saved:
            window?.close()
        case .savedToFallback(let url):
            Notifier.show(title: "저장 위치 폴백", body: "데스크탑에 저장했습니다: \(url.lastPathComponent)")
            window?.close()
        case .failed(let error):
            Notifier.alertFailure(title: "저장 실패", body: error.localizedDescription)
        }
    }

    @objc public func performOCR() {
        guard !isRecognizing else { return }
        isRecognizing = true
        TextRecognizer.recognize(image) { [weak self] result in
            guard let self else { return }
            self.isRecognizing = false
            switch result {
            case .success(let text) where text.isEmpty:
                self.canvas.showToast("인식된 텍스트가 없습니다")
            case .success(let text):
                ClipboardWriter.write(text: text)
                self.canvas.showToast("\(text.count)자를 복사했습니다")
            case .failure(let error):
                Notifier.alertFailure(title: "OCR 실패", body: error.localizedDescription)
            }
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
