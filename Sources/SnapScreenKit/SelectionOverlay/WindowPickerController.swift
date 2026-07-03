import AppKit
import ScreenCaptureKit

@MainActor
public final class WindowPickerController {
    public struct PickTarget {
        public let window: SCWindow
        public let frameInScreenPoints: CGRect
    }

    private var panels: [PickerPanel] = []
    private var completion: ((PickTarget?) -> Void)?
    private var targets: [PickTarget] = []

    public init() {}

    /// windows: CaptureEngine.shareableWindows() 결과 (앞쪽 창이 배열 앞)
    public func begin(windows: [SCWindow], completion: @escaping (PickTarget?) -> Void) {
        self.completion = completion
        // 주의: hover 최전면 판정은 SCShareableContent.windows의 front-to-back 순서에 의존한다.
        // CG 전역 좌표(주 화면 좌상단 원점) → Cocoa 전역 좌표
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        targets = windows.map { w in
            let f = w.frame
            let cocoa = CGRect(x: f.minX, y: primaryHeight - f.maxY,
                               width: f.width, height: f.height)
            return PickTarget(window: w, frameInScreenPoints: cocoa)
        }
        for screen in NSScreen.screens {
            let panel = PickerPanel(screen: screen, targets: targets) { [weak self] target in
                self?.finish(with: target)
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        if let keyPanel = panels.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? panels.first {
            keyPanel.makeKey()
            keyPanel.makeFirstResponder(keyPanel.contentView)
        }
    }

    private func finish(with target: PickTarget?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        let done = completion
        completion = nil
        done?(target)
    }
}

private final class PickerPanel: NSPanel {
    private let onFinish: (WindowPickerController.PickTarget?) -> Void

    init(screen: NSScreen, targets: [WindowPickerController.PickTarget],
         onFinish: @escaping (WindowPickerController.PickTarget?) -> Void) {
        self.onFinish = onFinish
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        contentView = PickerView(screen: screen, targets: targets, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onFinish(nil) }
}

private final class PickerView: NSView {
    private let screen: NSScreen
    private let targets: [WindowPickerController.PickTarget]
    private let onFinish: (WindowPickerController.PickTarget?) -> Void
    private var hovered: WindowPickerController.PickTarget?
    private var trackingArea: NSTrackingArea?

    init(screen: NSScreen, targets: [WindowPickerController.PickTarget],
         onFinish: @escaping (WindowPickerController.PickTarget?) -> Void) {
        self.screen = screen
        self.targets = targets
        self.onFinish = onFinish
        super.init(frame: screen.frame)
        updateHover(at: NSEvent.mouseLocation)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .activeAlways],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // esc
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: NSEvent.mouseLocation)
    }

    private func updateHover(at globalPoint: CGPoint) {
        // targets는 앞 창부터 정렬되어 있으므로 첫 매치가 최전면 창
        hovered = targets.first { $0.frameInScreenPoints.contains(globalPoint) }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        onFinish(hovered)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.35).setFill()
        bounds.fill()
        guard let hovered else { return }
        // 전역 좌표 → 이 화면 로컬 좌표
        let local = hovered.frameInScreenPoints
            .offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            .intersection(bounds)
        guard !local.isEmpty else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.3).setFill()
        local.fill()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(rect: local)
        path.lineWidth = 2
        path.stroke()
    }
}
