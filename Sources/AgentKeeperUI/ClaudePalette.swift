import SwiftUI
import AppKit

/// 品牌色系：陶土橙 accent + **macOS 系统语义色**（标杆软件同款——Finder/系统设置/邮件）。
/// 日夜间全部取系统标准值：windowBackgroundColor 底、controlBackgroundColor 卡片、
/// textColor 主文字——不再自造近似 hex，保证各外观下对比度与系统一致。
@MainActor
public enum ClaudePalette {
    /// 陶土橙（Claude accent，#D97757）。全 App 唯一品牌定制色。
    public static let accent = Color(hex: 0xD97757)
    /// 窗口底（日间系统灰白档 / 夜间系统深档）。
    public static let background = Color(nsColor: .windowBackgroundColor)
    /// 卡片/面板底（日间白档 / 夜间抬升深档）。
    public static let card = Color(nsColor: .controlBackgroundColor)
    /// 主文字（日间近纯黑,不再发浅；夜间白）。
    public static let textPrimary = Color(nsColor: .textColor)
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
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
