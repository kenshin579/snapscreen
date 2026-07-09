import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator!
    private var statusItemController: StatusItemController!
    private var settingsController: SettingsWindowController?
    private let activationPolicyManager = ActivationPolicyManager()
    private var homeWindowController: HomeWindowController?
    private var historyStore: HistoryStore!
    public private(set) var updateState = UpdateState()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuBuilder.install()
        coordinator = CaptureCoordinator()
        coordinator.policyManager = activationPolicyManager

        let historyDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnapScreen/History", isDirectory: true)
        historyStore = HistoryStore(directory: historyDir)
        coordinator.historyStore = historyStore

        homeWindowController = HomeWindowController(
            policyManager: activationPolicyManager,
            history: historyStore,
            onCapture: { [weak coordinator] mode in coordinator?.beginCapture(mode) },
            onOpenEntry: { [weak coordinator, weak self] entry in
                guard let coordinator, let self else { return }
                if let image = self.historyStore.loadImage(id: entry.id) {
                    coordinator.openFromHistory(image: image, scale: entry.scale)
                } else {
                    Notifier.show(title: "열 수 없음", body: "원본 파일을 찾지 못했습니다")
                    self.historyStore.remove(id: entry.id)
                }
            })
        homeWindowController?.show()

        statusItemController = StatusItemController(
            coordinator: coordinator,
            updateState: updateState,
            openHome: { [weak self] in self?.homeWindowController?.show() },
            openSettings: { [weak self] in
                guard let self else { return }
                if self.settingsController == nil {
                    self.settingsController = SettingsWindowController(
                        settings: self.coordinator.settings,
                        updateState: self.updateState,
                        policyManager: self.activationPolicyManager)
                }
                self.settingsController?.show()
            })
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
