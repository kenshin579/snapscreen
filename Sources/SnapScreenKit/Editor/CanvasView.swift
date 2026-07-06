import AppKit

@MainActor
public final class CanvasView: NSView, NSTextFieldDelegate {
    var image: CGImage
    let captureScale: CGFloat
    let store: AnnotationStore
    let state: EditorState
    var selectedID: UUID?

    private enum DragMode {
        case none
        case drawing(start: CGPoint)
        case moving(id: UUID, last: CGPoint, total: CGVector)
    }
    private var dragMode: DragMode = .none
    private var draft: Annotation?
    private var textField: NSTextField?
    private var pendingTextOrigin: CGPoint?

    // crop 모드 (이미지 픽셀 좌하단 좌표)
    private var isCropping = false
    private var cropStart: CGPoint?
    private var cropRect: CGRect?
    private var cropConfirmButton: NSButton?
    private var cropCancelButton: NSButton?
    /// 확정된 crop 영역(이미지 픽셀 좌표)을 컨트롤러에 전달
    var onCropConfirmed: ((CGRect) -> Void)?

    // 펜 자유곡선 그리기 중 누적 점열 (이미지 픽셀 좌표). nil이면 펜 드로잉 중 아님.
    private var penPoints: [CGPoint]?

    /// 캡처 배율 기준 기본 크기 (Retina에서 주석이 너무 얇아지지 않게)
    private var defaultLineWidth: CGFloat { 3 * captureScale }
    private var defaultFontSize: CGFloat { 16 * captureScale }
    private var badgeRadius: CGFloat { 14 * captureScale }

    /// 뷰 포인트 → 이미지 픽셀 배율 (aspect fit)
    var fitScale: CGFloat {
        min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
    }

    /// 레터박스 오프셋 (뷰 포인트): 이미지를 캔버스 중앙에 배치
    var fitOffset: CGPoint {
        CGPoint(x: (bounds.width - CGFloat(image.width) * fitScale) / 2,
                y: (bounds.height - CGFloat(image.height) * fitScale) / 2)
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
        return CGPoint(x: (p.x - fitOffset.x) / fitScale,
                       y: (p.y - fitOffset.y) / fitScale)
    }

    /// crop 등으로 캔버스 이미지를 교체
    func replaceImage(_ newImage: CGImage) {
        image = newImage
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        ctx.saveGState()
        ctx.translateBy(x: fitOffset.x, y: fitOffset.y)
        ctx.scaleBy(x: fitScale, y: fitScale)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        for annotation in store.annotations {
            if case .moving(let id, _, let total) = dragMode, annotation.id == id {
                var moved = annotation
                moved.kind = annotation.kind.translated(by: total)
                AnnotationRenderer.draw(moved, in: ctx, baseImage: image, scale: captureScale)
            } else {
                AnnotationRenderer.draw(annotation, in: ctx, baseImage: image, scale: captureScale)
            }
        }
        drawOverlays(in: ctx)
        ctx.restoreGState()
    }

    func drawOverlays(in ctx: CGContext) {
        if let draft {
            AnnotationRenderer.draw(draft, in: ctx, baseImage: image, scale: captureScale)
        }
        if let selectedID,
           let selected = store.annotations.first(where: { $0.id == selectedID }) {
            var bounds = selected.kind.bounds
            if case .moving(let id, _, let total) = dragMode, id == selectedID {
                bounds = bounds.offsetBy(dx: total.dx, dy: total.dy)
            }
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5 * captureScale)
            ctx.setLineDash(phase: 0, lengths: [4 * captureScale, 4 * captureScale])
            ctx.stroke(bounds.insetBy(dx: -6 * captureScale, dy: -6 * captureScale))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if isCropping {
            let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            ctx.setFillColor(NSColor(white: 0, alpha: 0.4).cgColor)
            if let rect = cropRect {
                let path = CGMutablePath()
                path.addRect(imageRect)
                path.addRect(rect)
                ctx.addPath(path)
                ctx.fillPath(using: .evenOdd)
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                ctx.setLineWidth(1.0 / fitScale)
                ctx.stroke(rect)
            } else {
                ctx.fill(imageRect)
            }
        }
    }

    // MARK: - Mouse

    public override func mouseDown(with event: NSEvent) {
        commitTextFieldIfNeeded()
        let p = imagePoint(from: event)
        if isCropping {
            cropStart = clampToImage(p)
            cropRect = nil
            removeCropButtons()
            needsDisplay = true
            return
        }
        // 레터박스(이미지 밖) 클릭은 무시 — flatten 시 유실될 주석 생성 방지
        guard (0...CGFloat(image.width)).contains(p.x),
              (0...CGFloat(image.height)).contains(p.y) else { return }

        if let hit = AnnotationHitTester.hitTest(p, annotations: store.annotations,
                                                 tolerance: 8 * captureScale) {
            selectedID = hit.id
            dragMode = .moving(id: hit.id, last: p, total: .zero)
            needsDisplay = true
            return
        }
        selectedID = nil

        switch state.tool {
        case .text:
            beginTextInput(at: p, viewPoint: convert(event.locationInWindow, from: nil))
        case .stepBadge:
            store.add(Annotation(kind: .stepBadge(center: p, number: store.nextStepNumber,
                                                  radius: badgeRadius),
                                 color: state.color, lineWidth: defaultLineWidth))
            needsDisplay = true
        case .pen:
            penPoints = [p]
            draft = Annotation(kind: .path([p]), color: state.color, lineWidth: defaultLineWidth)
        default:
            dragMode = .drawing(start: p)
        }
        needsDisplay = true
    }

    public override func mouseDragged(with event: NSEvent) {
        if isCropping, let start = cropStart {
            let p = clampToImage(imagePoint(from: event))
            cropRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                              width: abs(start.x - p.x), height: abs(start.y - p.y))
            needsDisplay = true
            return
        }
        if penPoints != nil {
            let p = imagePoint(from: event)
            penPoints?.append(p)
            if let pts = penPoints { draft?.kind = .path(pts) }
            needsDisplay = true
            return
        }
        let p = imagePoint(from: event)
        switch dragMode {
        case .drawing(let start):
            draft = makeDraft(from: start, to: p)
            needsDisplay = true
        case .moving(let id, let last, let total):
            let delta = CGVector(dx: p.x - last.x, dy: p.y - last.y)
            dragMode = .moving(id: id, last: p,
                               total: CGVector(dx: total.dx + delta.dx, dy: total.dy + delta.dy))
            needsDisplay = true
        case .none:
            break
        }
    }

    public override func mouseUp(with event: NSEvent) {
        if isCropping {
            cropStart = nil
            if let rect = cropRect, rect.width >= 8, rect.height >= 8 {
                showCropButtons(for: rect)
            } else {
                cropRect = nil
            }
            needsDisplay = true
            return
        }
        if let pts = penPoints {
            if pts.count >= 2, let draft { store.add(draft) }
            penPoints = nil
            draft = nil
            needsDisplay = true
            return
        }
        switch dragMode {
        case .drawing:
            if let draft, draft.kind.bounds.width >= 3 || draft.kind.bounds.height >= 3 {
                store.add(draft)
            }
            draft = nil
        case .moving(let id, _, let total):
            if total.dx != 0 || total.dy != 0 {
                store.translate(id: id, by: total) // undo 1회로 커밋
            }
        case .none:
            break
        }
        dragMode = .none
        needsDisplay = true
    }

    private func makeDraft(from start: CGPoint, to p: CGPoint) -> Annotation {
        let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                          width: abs(start.x - p.x), height: abs(start.y - p.y))
        let kind: AnnotationKind
        switch state.tool {
        case .arrow: kind = .arrow(start: start, end: p)
        case .rectangle: kind = .rectangle(rect)
        case .ellipse: kind = .ellipse(rect)
        case .pixelate: kind = .pixelate(rect)
        case .blur: kind = .blur(rect)
        case .text, .stepBadge, .pen: kind = .rectangle(rect) // 도달하지 않음 (mouseDown에서 처리)
        }
        return Annotation(kind: kind, color: state.color, lineWidth: defaultLineWidth)
    }

    // MARK: - Keyboard

    public override func keyDown(with event: NSEvent) {
        if isCropping {
            switch event.keyCode {
            case 36, 76: confirmCrop(); return   // return, enter
            case 53: endCrop(); return            // esc
            default: break
            }
        }
        switch event.keyCode {
        case 51, 117: // delete, forward delete
            if let selectedID {
                store.remove(id: selectedID)
                self.selectedID = nil
                needsDisplay = true
            }
        case 53: // esc
            selectedID = nil
            needsDisplay = true
        default:
            guard !event.modifierFlags.contains(.command) else {
                return super.keyDown(with: event)
            }
            guard let char = event.charactersIgnoringModifiers?.lowercased() else {
                return super.keyDown(with: event)
            }
            let mapping: [String: EditorTool] = [
                "a": .arrow, "r": .rectangle, "o": .ellipse,
                "t": .text, "g": .blur, "b": .pixelate, "n": .stepBadge,
                "p": .pen
            ]
            if let tool = mapping[char] {
                state.tool = tool
            } else if char == "c", store.annotations.isEmpty {
                beginCrop()
            } else {
                super.keyDown(with: event)
            }
        }
    }

    // MARK: - Crop

    func beginCrop() {
        commitTextFieldIfNeeded()
        // 미커밋 텍스트가 방금 주석으로 커밋됐을 수 있으므로 재검증 — 주석이 있으면 crop 진입 안 함
        guard store.annotations.isEmpty else { return }
        selectedID = nil
        isCropping = true
        cropStart = nil
        cropRect = nil
        removeCropButtons()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    /// crop 모드 중 도구가 전환된 경우 등, 활성 상태일 때만 crop을 취소
    func cancelCropIfActive() {
        if isCropping { endCrop() }
    }

    private func endCrop() {
        isCropping = false
        cropStart = nil
        cropRect = nil
        removeCropButtons()
        needsDisplay = true
    }

    private func removeCropButtons() {
        cropConfirmButton?.removeFromSuperview(); cropConfirmButton = nil
        cropCancelButton?.removeFromSuperview(); cropCancelButton = nil
    }

    private func confirmCrop() {
        guard let rect = cropRect, rect.width >= 8, rect.height >= 8 else { return }
        let confirmed = rect
        endCrop()
        onCropConfirmed?(confirmed)
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, p.x), CGFloat(image.width)),
                y: min(max(0, p.y), CGFloat(image.height)))
    }

    /// crop rect(이미지 픽셀 좌표)를 뷰 좌표로 변환한 우하단 근처에 ✓/✗ 버튼 배치
    private func showCropButtons(for rect: CGRect) {
        removeCropButtons()
        let viewMaxX = fitOffset.x + rect.maxX * fitScale
        let viewMinY = fitOffset.y + rect.minY * fitScale
        let size: CGFloat = 28
        let gap: CGFloat = 6

        let confirm = NSButton(frame: CGRect(x: viewMaxX - size * 2 - gap,
                                             y: viewMinY + gap, width: size, height: size))
        confirm.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "자르기 확정")
        confirm.target = self
        confirm.action = #selector(cropConfirmClicked)
        confirm.toolTip = "자르기 (⏎)"
        styleCropButton(confirm, background: NSColor.systemGreen.withAlphaComponent(0.8))

        let cancel = NSButton(frame: CGRect(x: viewMaxX - size, y: viewMinY + gap,
                                            width: size, height: size))
        cancel.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "자르기 취소")
        cancel.target = self
        cancel.action = #selector(cropCancelClicked)
        cancel.toolTip = "취소 (esc)"
        styleCropButton(cancel, background: NSColor.systemRed.withAlphaComponent(0.8))

        addSubview(confirm); addSubview(cancel)
        cropConfirmButton = confirm; cropCancelButton = cancel
    }

    /// 흰/어두운 배경 어디서든 대비를 확보하도록 원형 색 배경 + 흰 심볼 + 그림자를 입힌다.
    /// (`.circular` bezelStyle은 배경색 지정이 안 먹어 레이어로 직접 그린다)
    private func styleCropButton(_ button: NSButton, background: NSColor) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.title = ""
        button.contentTintColor = .white
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        layer.backgroundColor = background.cgColor
        layer.cornerRadius = button.frame.height / 2
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: -1)
        layer.masksToBounds = false
    }

    @objc private func cropConfirmClicked() { confirmCrop() }
    @objc private func cropCancelClicked() { endCrop() }

    // MARK: - Text input

    private func beginTextInput(at imageOrigin: CGPoint, viewPoint: CGPoint) {
        // 커밋된 주석과 동일한 화면 크기: defaultFontSize(이미지 픽셀) × fitScale(이미지→뷰)
        let displayFontSize = defaultFontSize * fitScale
        let fieldHeight = displayFontSize * 1.5
        // 커밋된 텍스트는 origin이 글리프 좌하단 → 필드도 클릭점에서 위로 확장되도록 배치
        let field = NSTextField(frame: CGRect(x: viewPoint.x, y: viewPoint.y,
                                              width: max(220, displayFontSize * 14), height: fieldHeight))
        field.font = .boldSystemFont(ofSize: displayFontSize)
        field.textColor = state.color.nsColor
        field.delegate = self
        field.backgroundColor = NSColor(white: 1, alpha: 0.85)
        field.isBordered = true
        field.focusRingType = .none
        field.target = self
        field.action = #selector(textFieldCommitted(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        pendingTextOrigin = imageOrigin
    }

    @objc private func textFieldCommitted(_ sender: NSTextField) {
        commitTextFieldIfNeeded()
    }

    /// esc로 텍스트 입력 취소 (커밋 없이 필드 제거)
    public func control(_ control: NSControl, textView: NSTextView,
                        doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.removeFromSuperview()
            textField = nil
            pendingTextOrigin = nil
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func commitTextFieldIfNeeded() {
        guard let field = textField, let origin = pendingTextOrigin else { return }
        let string = field.stringValue.trimmingCharacters(in: .whitespaces)
        field.removeFromSuperview()
        textField = nil
        pendingTextOrigin = nil
        if !string.isEmpty {
            store.add(Annotation(kind: .text(origin: origin, string: string,
                                             fontSize: defaultFontSize),
                                 color: state.color, lineWidth: defaultLineWidth))
        }
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
}
