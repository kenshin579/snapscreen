import AppKit

public enum CaptureMode {
    case area, window, fullScreen
}

@MainActor
public final class CaptureCoordinator {
    private let engine = CaptureEngine()
    public let settings = SettingsStore()
    private var overlay: SelectionOverlayController?
    private var windowPicker: WindowPickerController?
    private var isPickingWindow = false
    private var editors: [EditorWindowController] = []
    public var policyManager: ActivationPolicyManager?
    public var historyStore: HistoryStore?

    public init() {
        settings.load()
    }

    public func beginCapture(_ mode: CaptureMode) {
        guard ScreenCapturePermission.ensurePermission() else { return }
        switch mode {
        case .fullScreen:
            let mouse = NSEvent.mouseLocation
            Task {
                do {
                    let result = try await self.engine.captureFullDisplay(containing: mouse)
                    self.handleCaptured(result)
                } catch {
                    Notifier.alertFailure(title: "캡처 실패", body: error.localizedDescription)
                }
            }
        case .area:
            guard overlay == nil else { return } // 중복 실행 방지
            let overlayController = SelectionOverlayController()
            overlay = overlayController
            overlayController.begin { [weak self] selection in
                guard let self else { return }
                self.overlay = nil
                guard let selection else { return }
                let cgRect = ScreenGeometry.cgRect(
                    fromScreenRect: selection.rectInScreenPoints,
                    screenFrame: selection.screen.frame)
                let displayID = selection.screen.displayID
                let scale = selection.screen.backingScaleFactor
                Task {
                    do {
                        let result = try await self.engine.captureArea(
                            rect: cgRect, displayID: displayID, scale: scale)
                        self.handleCaptured(result)
                    } catch {
                        Notifier.alertFailure(title: "캡처 실패", body: error.localizedDescription)
                    }
                }
            }
        case .window:
            guard !isPickingWindow else { return }
            isPickingWindow = true
            Task {
                do {
                    let windows = try await self.engine.shareableWindows()
                    let picker = WindowPickerController()
                    self.windowPicker = picker
                    picker.begin(windows: windows) { [weak self] target in
                        guard let self else { return }
                        self.windowPicker = nil
                        self.isPickingWindow = false
                        guard let target else { return }
                        Task {
                            do {
                                let result = try await self.engine.captureWindow(target.window)
                                self.handleCaptured(result)
                            } catch {
                                Notifier.alertFailure(title: "캡처 실패", body: error.localizedDescription)
                            }
                        }
                    }
                } catch {
                    self.isPickingWindow = false
                    Notifier.alertFailure(title: "캡처 실패", body: error.localizedDescription)
                }
            }
        }
    }

    func handleCaptured(_ result: CaptureResult) {
        openEditor(result)
        historyStore?.add(image: result.image, scale: result.scale)
    }

    /// 히스토리 항목을 편집기로 다시 연다(재기록 없음).
    /// 같은 항목의 편집기가 이미 열려 있으면 새 창 대신 기존 창을 포커스한다.
    public func openFromHistory(image: CGImage, scale: CGFloat, entryID: UUID) {
        if let existing = editors.first(where: { $0.historyEntryID == entryID }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        openEditor(CaptureResult(image: image, scale: scale), historyEntryID: entryID)
    }

    private func openEditor(_ result: CaptureResult, historyEntryID: UUID? = nil) {
        // controller가 onClose 클로저를 통해 자신을 보유하는 순환은
        // windowWillClose에서 onClose = nil로 끊긴다
        var controller: EditorWindowController?
        controller = EditorWindowController(result: result, settings: settings,
                                            policyManager: policyManager,
                                            historyEntryID: historyEntryID) { [weak self] in
            self?.editors.removeAll { $0 === controller }
        }
        if let controller { editors.append(controller) }
    }
}
