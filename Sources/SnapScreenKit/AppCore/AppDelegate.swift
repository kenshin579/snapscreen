import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator!
    private var statusItemController: StatusItemController!

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenuBuilder.install()
        coordinator = CaptureCoordinator()
        statusItemController = StatusItemController(coordinator: coordinator)
    }
}
