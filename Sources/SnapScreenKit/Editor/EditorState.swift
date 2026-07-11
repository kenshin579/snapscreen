import Foundation
import CoreGraphics

public enum EditorTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, ellipse, text, blur, pixelate, stepBadge, pen, eraser
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .arrow: return "화살표"
        case .rectangle: return "사각형"
        case .ellipse: return "원"
        case .text: return "텍스트"
        case .blur: return "블러 (시각적 완화용 — 민감정보는 모자이크 사용)"
        case .pixelate: return "모자이크 (민감정보 가리기)"
        case .stepBadge: return "번호"
        case .pen: return "펜"
        case .eraser: return "지우개"
        }
    }

    public var symbolName: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .pixelate: return "mosaic"
        case .stepBadge: return "1.circle"
        case .pen: return "scribble"
        case .eraser: return "eraser"
        }
    }
}

@MainActor
public final class EditorState: ObservableObject {
    @Published public var tool: EditorTool = .arrow
    @Published public var color: PaletteColor = .red
    @Published public var lineWidth: CGFloat = 3       // 인스펙터 슬라이더 (points, pre-scale)
    @Published public var shadowEnabled: Bool = true   // 인스펙터 토글
    public init() {}
}
