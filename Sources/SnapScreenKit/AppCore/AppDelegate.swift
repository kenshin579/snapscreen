import AppKit
import Combine

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator!
    private var statusItemController: StatusItemController!
    private var settingsController: SettingsWindowController?
    private let activationPolicyManager = ActivationPolicyManager()
    private var homeWindowController: HomeWindowController?
    private var historyStore: HistoryStore!
    private var historyLimitCancellable: AnyCancellable?
    public private(set) var updateState = UpdateState()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        MainMenuBuilder.install()
        coordinator = CaptureCoordinator()
        coordinator.policyManager = activationPolicyManager

        let historyDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnapScreen/History", isDirectory: true)
        historyStore = HistoryStore(directory: historyDir, limit: coordinator.settings.historyLimit)
        coordinator.historyStore = historyStore
        historyLimitCancellable = coordinator.settings.$historyLimit.sink { [weak historyStore] limit in
            historyStore?.updateLimit(limit)
        }

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
            },
            onOpenSettings: { [weak self] in self?.openSettings(nil) })
        homeWindowController?.show()

        statusItemController = StatusItemController(
            coordinator: coordinator,
            updateState: updateState,
            openHome: { [weak self] in self?.homeWindowController?.show() },
            openSettings: { [weak self] in self?.openSettings(nil) })
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

    /// 설정 창 열기. App 메뉴 "설정…"(⌘,)의 nil-target 셀렉터가 응답 체인으로 도달하고,
    /// 메뉴바 아이콘의 "설정…"도 이 메서드를 호출한다.
    @objc public func openSettings(_ sender: Any?) {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                settings: coordinator.settings,
                updateState: updateState,
                policyManager: activationPolicyManager)
        }
        settingsController?.show()
    }
}
