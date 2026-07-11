import SwiftUI

/// 단축키 표시용 키캡 칩. 글자 하나(예: "⌘", "⇧", "1")를 받는다.
/// 여러 칩은 호출부에서 `ShortcutKeycaps.decompose(...)` 결과를 `ForEach`로 나열해 조합한다.
public struct KeycapChip: View {
    private let text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(DesignTokens.Typography.keycap)
            .foregroundStyle(DesignTokens.Colors.keycapText)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(DesignTokens.Colors.keycapFill)
            // 하단 2px 바 — 키캡 입체감
            .overlay(alignment: .bottom) {
                DesignTokens.Colors.keycapBorder
                    .frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap))
            // 1px 전체 테두리
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap)
                    .strokeBorder(DesignTokens.Colors.keycapBorder, lineWidth: 1))
    }
}

#Preview {
    HStack(spacing: 3) {
        KeycapChip("⌘")
        KeycapChip("⇧")
        KeycapChip("1")
    }
    .padding()
}
