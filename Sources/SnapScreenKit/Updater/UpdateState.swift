import Foundation

@MainActor
public final class UpdateState: ObservableObject {
    public enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String, downloadURL: URL)
        case installing
        case failed(String)
    }

    @Published public var phase: Phase = .idle

    public init() {}

    /// quiet=true(시작 시 자동 확인): 실패해도 조용히 .idle로 되돌린다 (스펙 §7)
    public func check(quiet: Bool = false) async {
        guard phase != .checking, phase != .installing else { return }
        phase = .checking
        switch await UpdateChecker.check() {
        case .upToDate:
            phase = .upToDate
        case .available(let version, let downloadURL):
            phase = .available(version: version, downloadURL: downloadURL)
        case .failed(let message):
            phase = quiet ? .idle : .failed(message)
        }
    }
}
