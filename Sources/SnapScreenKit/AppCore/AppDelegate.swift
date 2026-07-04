import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator!
    private var statusItemController: StatusItemController!
    private var settingsController: SettingsWindowController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenuBuilder.install()
        coordinator = CaptureCoordinator()
        statusItemController = StatusItemController(coordinator: coordinator) { [weak self] in
            guard let self else { return }
            if self.settingsController == nil {
                self.settingsController = SettingsWindowController(settings: self.coordinator.settings)
            }
            self.settingsController?.show()
        }
        Hotkeys.register(coordinator: coordinator)
        Notifier.requestAuthorization()
    }
}
