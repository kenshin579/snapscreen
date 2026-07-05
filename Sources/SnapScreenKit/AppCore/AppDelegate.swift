import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator!
    private var statusItemController: StatusItemController!
    private var settingsController: SettingsWindowController?
    public private(set) var updateState = UpdateState()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainMenuBuilder.install()
        coordinator = CaptureCoordinator()
        statusItemController = StatusItemController(coordinator: coordinator) { [weak self] in
            guard let self else { return }
            if self.settingsController == nil {
                self.settingsController = SettingsWindowController(
                    settings: self.coordinator.settings,
                    updateState: self.updateState)
            }
            self.settingsController?.show()
        }
        Hotkeys.register(coordinator: coordinator)
        Notifier.requestAuthorization()

        // 시작 시 자동 업데이트 확인 (실패 시 조용히 무시)
        Task { await updateState.check(quiet: true) }

        // 업데이트 후 첫 실행이면 권한 재승인 안내 (ad-hoc 서명 제약)
        let lastRunKey = "lastRunVersion"
        let lastRun = UserDefaults.standard.string(forKey: lastRunKey)
        if let lastRun, lastRun != AppInfo.version {
            Notifier.show(title: "SnapScreen \(AppInfo.version)(으)로 업데이트됨",
                          body: "화면 기록 권한을 다시 켜야 할 수 있습니다.")
        }
        UserDefaults.standard.set(AppInfo.version, forKey: lastRunKey)
    }
}
