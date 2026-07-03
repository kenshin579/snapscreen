import AppKit

public enum CaptureMode {
    case area, window, fullScreen
}

@MainActor
public final class CaptureCoordinator {
    private let engine = CaptureEngine()
    public let settings = SettingsStore()

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
            break // Task 10
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
