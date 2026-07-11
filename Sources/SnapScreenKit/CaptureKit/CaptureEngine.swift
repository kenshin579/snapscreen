import AppKit
import ScreenCaptureKit

public struct CaptureResult {
    public let image: CGImage
    /// 캡처 당시 디스플레이 배율 (PNG DPI 메타데이터, 주석 크기 산정에 사용)
    public let scale: CGFloat
}

public enum CaptureError: LocalizedError {
    case displayNotFound
    public var errorDescription: String? {
        switch self {
        case .displayNotFound: return L("Could not find the display to capture.")
        }
    }
}

public final class CaptureEngine {
    public init() {}

    /// 전체 화면: point(Cocoa 전역 좌표)가 속한 디스플레이 전체
    @MainActor
    public func captureFullDisplay(containing point: CGPoint) async throws -> CaptureResult {
        guard let screen = NSScreen.screen(containing: point) else {
            throw CaptureError.displayNotFound
        }
        let (displayID, scale) = (screen.displayID, screen.backingScaleFactor)
        return try await capture(displayID: displayID, sourceRect: nil, scale: scale)
    }

    /// 영역: rect는 디스플레이 로컬 CG 좌표(원점 좌상단, 포인트)
    public func captureArea(rect: CGRect, displayID: CGDirectDisplayID,
                            scale: CGFloat) async throws -> CaptureResult {
        try await capture(displayID: displayID, sourceRect: rect, scale: scale)
    }

    public func captureWindow(_ window: SCWindow) async throws -> CaptureResult {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let config = configuration(size: filter.contentRect.size, scale: scale)
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: config)
        return CaptureResult(image: image, scale: scale)
    }

    /// 창 선택 UI용 창 목록 (일반 레이어의 화면 표시 중인 창만, 우리 앱 창 제외)
    public func shareableWindows() async throws -> [SCWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let ourPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return content.windows.filter {
            $0.isOnScreen && $0.windowLayer == 0
                && $0.owningApplication?.processID != ourPID
                && $0.frame.width >= 40 && $0.frame.height >= 40
        }
    }

    private func capture(displayID: CGDirectDisplayID, sourceRect: CGRect?,
                         scale: CGFloat) async throws -> CaptureResult {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        // 우리 앱 창(오버레이 등)은 캡처에서 제외
        let ourWindows = content.windows.filter {
            $0.owningApplication?.processID == pid_t(ProcessInfo.processInfo.processIdentifier)
        }
        let filter = SCContentFilter(display: display, excludingWindows: ourWindows)
        let size = sourceRect?.size ?? CGSize(width: display.width, height: display.height)
        let config = configuration(size: size, scale: scale)
        if let sourceRect { config.sourceRect = sourceRect }
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                               configuration: config)
        return CaptureResult(image: image, scale: scale)
    }

    private func configuration(size: CGSize, scale: CGFloat) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        let px = ScreenGeometry.pixelSize(pointSize: size, scale: scale)
        config.width = Int(px.width.rounded())
        config.height = Int(px.height.rounded())
        config.showsCursor = false
        config.captureResolution = .best
        return config
    }
}
