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

    public init(result: CaptureResult, settings: SettingsStore,
                policyManager: ActivationPolicyManager? = nil,
                onClose: (() -> Void)? = nil) {
        self.result = result
        self.image = result.image
        self.settings = settings
        self.policyManager = policyManager
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
        window.minSize = NSSize(width: 320, height: 44 + 120) // 툴바 압착 방지

        canvas = CanvasView(image: self.image, captureScale: result.scale,
                            store: store, state: state)
        canvas.onCropConfirmed = { [weak self] rect in
            self?.applyCrop(rect)
        }
        canvas.onRequestOCR = { [weak self] in self?.performOCR() }
        let toolbar = NSHostingView(rootView: ToolbarView(
            state: state,
            store: store,
            onCrop: { [weak self] in self?.canvas.beginCrop() },
            onOCR: { [weak self] in self?.performOCR() },
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
        policyManager?.register(window)
        NSApp.activate(ignoringOtherApps: true)

        // 도구 전환(단축키/툴바 세그먼트) 시 진행 중인 crop을 자동 취소해 상태 불일치 방지
        toolCancellable = state.$tool.sink { [weak self] _ in
            self?.canvas.cancelCropIfActive()
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    public func windowWillClose(_ notification: Notification) {
        if let window { policyManager?.unregister(window) }
        onClose?() // 스펙: 닫으면 경고 없이 폐기
        onClose = nil
    }

    private func flattened() -> CGImage? {
        FlattenRenderer.flatten(image: image, annotations: store.annotations, scale: result.scale)
    }

    private func applyCrop(_ rect: CGRect) {
        // nil = 빈/무효 선택 → crop 취소, 원본·창 크기 보존
        guard let cropped = ImageCropper.crop(image, toBottomLeftRect: rect) else { return }
        image = cropped
        canvas.replaceImage(cropped)
        resizeWindowToImage()
    }

    /// 현재 이미지 비율에 맞게 창 content 크기 재조정 (init 사이징 규칙과 동일)
    private func resizeWindowToImage() {
        guard let window else { return }
        let pointSize = CGSize(width: CGFloat(image.width) / result.scale,
                               height: CGFloat(image.height) / result.scale)
        let maxSize = NSScreen.main.map { CGSize(width: $0.visibleFrame.width * 0.8,
                                                 height: $0.visibleFrame.height * 0.8) }
            ?? CGSize(width: 1200, height: 800)
        let fit = min(1, maxSize.width / pointSize.width, maxSize.height / pointSize.height)
        let contentSize = CGSize(width: pointSize.width * fit, height: pointSize.height * fit)
        let toolbarHeight: CGFloat = 44
        window.setContentSize(CGSize(width: contentSize.width,
                                     height: contentSize.height + toolbarHeight))
    }

    // MARK: - 메인 메뉴 액션 (MainMenuBuilder의 nil-target 셀렉터가 응답 체인으로 도달)

    @objc public func copyMerged(_ sender: Any?) {
        guard let image = flattened() else { return }
        ClipboardWriter.write(image, scale: result.scale)
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
        // 연속 실행(E 키 반복 등) 중 인식 중첩 방지 — 중복 클립보드 기록/알림 회피
        guard !isRecognizing else { return }
        isRecognizing = true
        TextRecognizer.recognize(image) { [weak self] result in
            guard let self else { return }
            self.isRecognizing = false
            switch result {
            case .success(let text) where text.isEmpty:
                Notifier.show(title: "텍스트 없음", body: "이미지에서 인식된 텍스트가 없습니다")
            case .success(let text):
                ClipboardWriter.write(text: text)
                Notifier.show(title: "텍스트 복사됨", body: "\(text.count)자를 클립보드에 복사했습니다")
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
