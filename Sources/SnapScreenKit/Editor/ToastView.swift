import AppKit

/// 편집기 캔버스 위에 잠깐 뜨는 반투명 pill 메시지 뷰.
@MainActor
final class ToastView: NSView {
    private let label = NSTextField(labelWithString: "")

    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = 10
        label.stringValue = message
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 13)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let s = label.intrinsicContentSize
        return NSSize(width: min(s.width, 360) + 32, height: s.height + 16)
    }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 16, dy: 8)
    }
}
