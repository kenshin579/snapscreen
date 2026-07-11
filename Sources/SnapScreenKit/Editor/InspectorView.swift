import SwiftUI

/// 편집기 우측 인스펙터 (폭 170). 색상·선 굵기·그림자·빠른 작업.
@MainActor
public struct InspectorView: View {
    @ObservedObject var state: EditorState
    let onCrop: () -> Void
    let onOCR: () -> Void

    public init(state: EditorState, onCrop: @escaping () -> Void, onOCR: @escaping () -> Void) {
        self.state = state
        self.onCrop = onCrop
        self.onOCR = onOCR
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("색상")
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(PaletteColor.allCases, id: \.self) { swatch($0) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    sectionLabel("선 굵기")
                    Spacer()
                    Text("\(Int(state.lineWidth))px")
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $state.lineWidth, in: 1...12, step: 1)
            }

            HStack {
                Text("그림자").font(.system(size: 12))
                Spacer()
                Toggle("", isOn: $state.shadowEnabled).labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("빠른 작업")
                quickButton("텍스트 추출", action: onOCR)
                quickButton("자르기", action: onCrop)
            }

            Spacer()
        }
        .padding(14)
        .frame(width: 170)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) { DesignTokens.Colors.hairline.frame(width: 1) }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func swatch(_ color: PaletteColor) -> some View {
        let selected = state.color == color
        return Circle()
            .fill(Color(nsColor: color.nsColor))
            .frame(width: 18, height: 18)
            // 선택 링: 2px 배경색 갭 + 3.5px 액센트 링
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor),
                                     lineWidth: selected ? 2 : 0).padding(-1.5))
            .overlay(Circle().stroke(Color.accentColor,
                                     lineWidth: selected ? 3 : 0).padding(-3.5))
            .contentShape(Circle())
            .onTapGesture { state.color = color }
    }

    private func quickButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6).padding(.horizontal, 8)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.button)
                    .fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}
