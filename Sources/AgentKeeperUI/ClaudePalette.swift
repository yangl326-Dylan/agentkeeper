import SwiftUI
import AppKit

/// Claude（Anthropic）品牌色系：陶土橙 accent + 象牙底 + 暖炭黑。
@MainActor
public enum ClaudePalette {
    /// 陶土橙（Claude accent，#D97757）。
    public static let accent = Color(hex: 0xD97757)
    /// 象牙底（亮 #F0EEE6）/ 暖炭底（暗 #262624）。
    public static let background = Color(dynamicLight: 0xF0EEE6, dark: 0x262624)
    /// 卡片/面板底（亮 #FAF9F5 / 暗 #30302E）。
    public static let card = Color(dynamicLight: 0xFAF9F5, dark: 0x30302E)
    /// 主文字（亮 #1F1E1D / 暗 #F0EEE6）。
    public static let textPrimary = Color(dynamicLight: 0x1F1E1D, dark: 0xF0EEE6)
}

// MARK: - 颜色构造

extension Color {
    /// sRGB 十六进制（0xRRGGBB）。
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// 亮/暗外观自适应色。
    init(dynamicLight: UInt32, dark: UInt32) {
        let light = NSColor(hex: dynamicLight)
        let darkColor = NSColor(hex: dark)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? darkColor : light
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
