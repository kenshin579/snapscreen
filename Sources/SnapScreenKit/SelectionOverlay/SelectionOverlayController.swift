import AppKit

@MainActor
public final class SelectionOverlayController {
    public struct Selection {
        public let rectInScreenPoints: CGRect // Cocoa 전역 좌표
        public let screen: NSScreen
    }

    private var panels: [OverlayPanel] = []
    private var completion: ((Selection?) -> Void)?

    public init() {}

    public func begin(completion: @escaping (Selection?) -> Void) {
        self.completion = completion
        for screen in NSScreen.screens {
            let panel = OverlayPanel(screen: screen) { [weak self] selection in
                self?.finish(with: selection)
            }
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        if let keyPanel = panels.first(where: { NSMouseInRect(mouse, $0.overlayScreen.frame, false) }) ?? panels.first {
            keyPanel.makeKey()
            keyPanel.makeFirstResponder(keyPanel.contentView)
        }
    }

    private func finish(with selection: Selection?) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        let done = completion
        completion = nil
        done?(selection)
    }
}

private final class OverlayPanel: NSPanel {
    let overlayScreen: NSScreen
    private let onFinish: (SelectionOverlayController.Selection?) -> Void

    init(screen: NSScreen, onFinish: @escaping (SelectionOverlayController.Selection?) -> Void) {
        self.onFinish = onFinish
        overlayScreen = screen
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = SelectionView(screen: screen, onFinish: onFinish)
    }

    override var canBecomeKey: Bool { true }

    /// first responder와 무관하게 패널이 key이면 esc 취소가 보장된다.
    override func cancelOperation(_ sender: Any?) { onFinish(nil) }
}

private final class SelectionView: NSView {
    private let screen: NSScreen
    private let onFinish: (SelectionOverlayController.Selection?) -> Void
    private var dragStart: CGPoint?
    private var selectionRect: CGRect?

    init(screen: NSScreen, onFinish: @escaping (SelectionOverlayController.Selection?) -> Void) {
        self.screen = screen
        self.onFinish = onFinish
        super.init(frame: screen.frame)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish(nil) } // esc
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = convert(event.locationInWindow, from: nil)
        window?.makeKey()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = convert(event.locationInWindow, from: nil)
        selectionRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                               width: abs(start.x - p.x), height: abs(start.y - p.y))
            .intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; selectionRect = nil }
        guard let rect = selectionRect, rect.width >= 4, rect.height >= 4 else {
            onFinish(nil) // 클릭만 하면 취소
            return
        }
        let global = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        onFinish(.init(rectInScreenPoints: global, screen: screen))
    }

    override func draw(_ dirtyRect: NSRect) {
        // 어둡게 깔고 선택 영역만 뚫는다
        NSColor(white: 0, alpha: 0.35).setFill()
        let dim = NSBezierPath(rect: bounds)
        if let rect = selectionRect {
            dim.appendRect(rect)
            dim.windingRule = .evenOdd
        }
        dim.fill()

        guard let rect = selectionRect else { return }
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect.insetBy(dx: -0.5, dy: -0.5))
        border.lineWidth = 1
        border.stroke()

        // 크기 라벨 (픽셀 단위)
        let scale = screen.backingScaleFactor
        let label = "\(Int(rect.width * scale)) × \(Int(rect.height * scale)) px" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
            .backgroundColor: NSColor(white: 0, alpha: 0.7)
        ]
        var origin = CGPoint(x: rect.maxX + 8, y: rect.minY - 20)
        let size = label.size(withAttributes: attrs)
        origin.x = min(origin.x, bounds.maxX - size.width - 4)
        origin.y = max(origin.y, 4)
        label.draw(at: origin, withAttributes: attrs)
    }
}
