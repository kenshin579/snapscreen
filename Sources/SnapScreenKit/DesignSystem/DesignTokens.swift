import SwiftUI
import AppKit

public enum DesignTokens {

    // MARK: - Colors
    /// 시스템 semantic이 없는 커스텀 색만 정의한다.
    /// 텍스트(primary/secondary/tertiary)·액센트는 SwiftUI semantic을 직접 쓴다.
    public enum Colors {
        /// hairline/border — 라이트 검정 8%, 다크 흰색 10%
        public static let hairline = dynamic(
            light: NSColor(white: 0, alpha: 0.08),
            dark: NSColor(white: 1, alpha: 0.10))

        /// 캡처 타일 배경 — 라이트 흰색 72%, 다크 흰색 7%
        public static let tileFill = dynamic(
            light: NSColor(white: 1, alpha: 0.72),
            dark: NSColor(white: 1, alpha: 0.07))

        /// 캡처 타일 테두리 — 라이트 검정 6%, 다크 흰색 10%
        public static let tileBorder = dynamic(
            light: NSColor(white: 0, alpha: 0.06),
            dark: NSColor(white: 1, alpha: 0.10))

        /// 어두운 타일 위 아이콘 액센트 틴트 — 라이트는 시스템 액센트, 다크는 #409CFF
        public static let accentIconTint = dynamic(
            light: NSColor(hex: 0x007AFF),
            dark: NSColor(hex: 0x409CFF))

        // MARK: 키캡 칩 (KeycapChip 소비)
        public static let keycapFill = dynamic(
            light: NSColor(white: 0, alpha: 0.05),
            dark: NSColor(white: 1, alpha: 0.09))
        public static let keycapBorder = dynamic(
            light: NSColor(white: 0, alpha: 0.10),
            dark: NSColor(white: 1, alpha: 0.14))
        public static let keycapText = dynamic(
            light: NSColor(hex: 0x3A3A3C),
            dark: NSColor(hex: 0xF5F5F7))
    }

    // MARK: - Radius
    public enum Radius {
        public static let window: CGFloat = 12
        public static let tile: CGFloat = 14
        public static let card: CGFloat = 12
        public static let thumb: CGFloat = 10
        public static let tool: CGFloat = 9
        public static let button: CGFloat = 8
        public static let sidebarRow: CGFloat = 8
        public static let iconTile: CGFloat = 7
        public static let keycap: CGFloat = 6
    }

    // MARK: - Typography
    public enum Typography {
        public static let windowTitle = Font.system(size: 13, weight: .semibold)
        public static let pageTitle = Font.system(size: 15, weight: .bold)
        public static let sectionLabel = Font.system(size: 12, weight: .semibold)
        public static let body = Font.system(size: 13)
        public static let button = Font.system(size: 12)
        public static let buttonProminent = Font.system(size: 12, weight: .semibold)
        public static let caption = Font.system(size: 11.5)
        public static let keycap = Font.system(size: 10.5, weight: .semibold, design: .monospaced)
        public static let mono = Font.system(size: 10.5, design: .monospaced)
    }

    // MARK: - Helpers
    /// 시스템 외관(aqua/darkAqua)에 따라 라이트/다크 색을 자동 선택하는 동적 색.
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

extension NSColor {
    /// 0xRRGGBB 형태의 정수로 sRGB 색 생성.
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
