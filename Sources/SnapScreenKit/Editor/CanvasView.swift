import AppKit

@MainActor
public final class CanvasView: NSView {
    let image: CGImage
    let captureScale: CGFloat
    let store: AnnotationStore
    let state: EditorState
    var selectedID: UUID?

    /// 뷰 포인트 → 이미지 픽셀 배율
    var fitScale: CGFloat {
        bounds.width / CGFloat(image.width)
    }

    public init(image: CGImage, captureScale: CGFloat, store: AnnotationStore, state: EditorState) {
        self.image = image
        self.captureScale = captureScale
        self.store = store
        self.state = state
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override var acceptsFirstResponder: Bool { true }

    func imagePoint(from event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / fitScale, y: p.y / fitScale)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.scaleBy(x: fitScale, y: fitScale)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        AnnotationRenderer.draw(store.annotations, in: ctx, baseImage: image, scale: captureScale)
        drawOverlays(in: ctx) // Task 14에서 드래프트/선택 표시 확장
        ctx.restoreGState()
    }

    func drawOverlays(in ctx: CGContext) {
        // Task 14에서 구현
    }
}
