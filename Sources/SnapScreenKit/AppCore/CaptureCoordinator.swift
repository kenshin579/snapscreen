import AppKit

public enum CaptureMode {
    case area, window, fullScreen
}

@MainActor
public final class CaptureCoordinator {
    public init() {}

    public func beginCapture(_ mode: CaptureMode) {
        // Task 9~11에서 구현. 지금은 메뉴 배선 확인용.
        NSSound.beep()
    }
}
