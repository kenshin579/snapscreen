import AppKit

/// 편집기 캔버스 위에 잠깐 뜨는 반투명 pill 메시지 뷰.
@MainActor
final class ToastView: NSView {
    init(message: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer?.cornerRadius = 10

        let label = NSTextField(labelWithString: message)
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 13)
        label.alignment = .center
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        // 오토레이아웃으로 label을 pin — 뷰 크기가 텍스트 폭 + 패딩에 정확히 맞아 잘림(…)이 없다.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}
