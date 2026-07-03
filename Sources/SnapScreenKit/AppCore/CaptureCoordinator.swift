import AppKit

public enum CaptureMode {
    case area, window, fullScreen
}

@MainActor
public final class CaptureCoordinator {
    private let engine = CaptureEngine()
    public let settings = SettingsStore()
    private var overlay: SelectionOverlayController?

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
            break // Task 11
        }
    }

    func handleCaptured(_ result: CaptureResult) {
        // Task 12에서 편집기 열기로 교체. 지금은 클립보드 + 파일 저장.
        ClipboardWriter.write(result.image, scale: result.scale)
        switch FileSaver(settings: settings).save(result.image, scale: result.scale) {
        case .saved:
            break
        case .savedToFallback(let url):
            Notifier.show(title: "저장 위치 폴백", body: "데스크탑에 저장했습니다: \(url.lastPathComponent)")
        case .failed(let error):
            Notifier.alertFailure(title: "저장 실패", body: error.localizedDescription)
        }
    }
}
