import Foundation
import CoreGraphics

public enum EditorTool: String, CaseIterable, Identifiable {
    case arrow, rectangle, ellipse, text, blur, pixelate, stepBadge, pen, eraser
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .arrow: return L("Arrow")
        case .rectangle: return L("Rectangle")
        case .ellipse: return L("Ellipse")
        case .text: return L("Text")
        case .blur: return L("Blur (visual softening — use Pixelate for sensitive info)")
        case .pixelate: return L("Pixelate (hide sensitive info)")
        case .stepBadge: return L("Number")
        case .pen: return L("Pen")
        case .eraser: return L("Eraser")
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
