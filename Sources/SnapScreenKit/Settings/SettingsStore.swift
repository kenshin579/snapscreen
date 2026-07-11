import Foundation

public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private enum Key {
        static let saveFolderOverride = "saveFolderOverride"
        static let filenamePrefix = "filenamePrefix"
        static let historyLimit = "historyLimit"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// nil이면 시스템 스크린샷 저장 위치를 따른다
    @Published public var saveFolderOverride: String? {
        didSet { defaults.set(saveFolderOverride, forKey: Key.saveFolderOverride) }
    }
    @Published public var filenamePrefix: String = "snapscreen" {
        didSet { defaults.set(filenamePrefix, forKey: Key.filenamePrefix) }
    }
    @Published public var historyLimit: Int = 50 {
        didSet { defaults.set(historyLimit, forKey: Key.historyLimit) }
    }

    public func load() {
        saveFolderOverride = defaults.string(forKey: Key.saveFolderOverride)
        filenamePrefix = defaults.string(forKey: Key.filenamePrefix) ?? "snapscreen"
        let storedLimit = defaults.integer(forKey: Key.historyLimit)
        historyLimit = storedLimit == 0 ? 50 : storedLimit
    }
}
