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
        var controller: EditorWindowController?
        controller = EditorWindowController(result: result, settings: settings) { [weak self] in
            self?.editors.removeAll { $0 === controller }
        }
        if let controller { editors.append(controller) }
    }
}
