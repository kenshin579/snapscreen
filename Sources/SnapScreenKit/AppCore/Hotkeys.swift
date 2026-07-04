import KeyboardShortcuts

public extension KeyboardShortcuts.Name {
    static let captureArea = Self("captureArea", default: .init(.one, modifiers: [.command, .shift]))
    static let captureWindow = Self("captureWindow", default: .init(.two, modifiers: [.command, .shift]))
    static let captureFullScreen = Self("captureFullScreen", default: .init(.zero, modifiers: [.command, .shift]))
}

@MainActor
public enum Hotkeys {
    public static func register(coordinator: CaptureCoordinator) {
        KeyboardShortcuts.onKeyUp(for: .captureArea) { coordinator.beginCapture(.area) }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { coordinator.beginCapture(.window) }
        KeyboardShortcuts.onKeyUp(for: .captureFullScreen) { coordinator.beginCapture(.fullScreen) }
    }
}
