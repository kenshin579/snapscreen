import AppKit
import SnapScreenKit

// Swift 6 언어 모드에서 main.swift 최상위 코드는 기본적으로 nonisolated이므로
// MainActor로 격리된 AppDelegate/NSApplication API 호출을 위해 명시적으로 격리한다.
@MainActor
func runApp() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

MainActor.assumeIsolated {
    runApp()
}
