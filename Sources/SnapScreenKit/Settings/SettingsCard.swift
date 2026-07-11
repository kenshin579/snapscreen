import SwiftUI

/// 설정 콘텐츠의 grouped 카드. 행(`SettingsRow`)들을 세로로 담고
/// 행 사이에는 호출부가 `SettingsRowDivider`를 끼워 넣는다.
struct SettingsCard<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(DesignTokens.Colors.settingsCard)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(DesignTokens.Colors.hairline, lineWidth: 1))
    }
}

/// 카드 안 한 행. 패딩 11×13, 좌측 정렬 HStack.
struct SettingsRow<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.vertical, 11)
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 행 사이 hairline (좌측 인셋 13).
struct SettingsRowDivider: View {
    var body: some View {
        DesignTokens.Colors.hairline
            .frame(height: 1)
            .padding(.leading, 13)
    }
}

/// 카드 아래 도움말 캡션.
struct SettingsCaption: View {
    private let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}
