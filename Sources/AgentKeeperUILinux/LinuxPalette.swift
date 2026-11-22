#if os(Linux)
import SwiftCrossUI
import AgentKeeperShared
import AppCore

/// 品牌色系（Linux 栈）：陶土橙 accent + 语义色。
/// 成对文件：Sources/AgentKeeperUI/ClaudePalette.swift（macOS 栈，hex 值由此抄写——
/// 平台纪律禁止跨 UI 栈 import，色值以注释对齐维护）。
/// SCUI 的 Color 无 NSColor 桥接：语义色用 GNOME/Adwaita 风格 hex 固定值 +
/// `adaptive(light:dark:)` 承接日夜间（macOS 侧走系统动态色，此处为最接近的静态近似）。
public enum LinuxPalette {
    // MARK: hex 原值（对齐 ClaudePalette 注释）

    /// 陶土橙（Claude accent，#D97757）——全 App 唯一品牌定制色。
    public static let accentHex: UInt32 = 0xD97757

    // MARK: 构造

    public static var accent: Color { Color(hex: accentHex) }

    /// 窗口底（日间浅灰白 / 夜间深档）——GNOME window 背景近似。
    public static var background: Color {
        Color.adaptive(light: Color(hex: 0xFAFAFA), dark: Color(hex: 0x242428))
    }

    /// 卡片/面板底（日间白 / 夜间抬升深档）。
    public static var card: Color {
        Color.adaptive(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x333338))
    }

    /// 主文字（日间近纯黑 / 夜间白）。
    public static var textPrimary: Color {
        Color.adaptive(light: Color(hex: 0x1A1A1A), dark: Color(hex: 0xF2F2F2))
    }

    /// 次级文字。
    public static var textSecondary: Color {
        Color.adaptive(light: Color(hex: 0x6E6E76), dark: Color(hex: 0xA8A8B0))
    }

    /// 选中行高亮（accent 低透明近似——SCUI Color 无 opacity 修饰链式前的静态合成）。
    public static var selection: Color {
        Color(hex: accentHex).opacity(0.16)
    }

    /// 行悬停/徽章底（中性低透明）。
    public static var subtle: Color {
        Color.adaptive(light: Color(hex: 0xEDEDF0), dark: Color(hex: 0x3A3A40))
    }

    // MARK: 语义色（红=需处理，琥珀=注意，绿=正常；对齐 macOS 侧 systemGreen/Orange/Red 观感）

    public static let green = Color(hex: 0x2EC27E)   // GNOME 绿
    public static let amber = Color(hex: 0xF5A623)   // 对齐 macOS 琥珀 Color(red:0.95,g:0.7,b:0.2)
    public static let red = Color(hex: 0xE01B24)     // GNOME 红
    public static let blue = Color(hex: 0x3584E4)    // GNOME 蓝
    public static let gray = Color(hex: 0x9A9AA0)

    /// StatusSemantics.colorKey（"green"|"amber"|"red"|"blue"|"gray"）→ Linux 栈颜色。
    /// 单一映射语义与 macOS RootView 的 semanticColor 扩展一一对应。
    public static func semantic(_ colorKey: String) -> Color {
        switch colorKey {
        case "green": green
        case "amber": amber
        case "red": red
        case "blue": blue
        default: gray
        }
    }
}

/// sRGB 十六进制（0xRRGGBB）→ SCUI Color（对齐 ClaudePalette 的 Color(hex:) 语义）。
extension Color {
    public init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, opacity: 1)
    }
}

/// 状态语义 → Linux 文字符号 + 颜色（v1 不追求 SF Symbols 等价物；
/// 符号单一来源：StatusSemantics.resolve 的 colorKey 语义 + 本表字形）。
/// （macOS 对应：RootView 内 Image(systemName:)；映射成对维护。）
public enum LinuxStatusGlyph {
    /// 行首状态符号（● 正常 / ■ 停用 / ▲ 注意 / ？未知）。
    public static func symbol(for token: StatusToken) -> String {
        switch token {
        case .enabled: "●"
        case .disabled: "■"
        case .changed: "▲"
        case .conflict: "▲"
        case .permissionDenied: "▲"
        case .unrecognized: "？"
        }
    }

    /// 扫描状态条符号。
    public static func scanSymbol(colorKey: String) -> String {
        switch colorKey {
        case "green": "●"
        case "blue": "◐"
        case "red": "▲"
        default: "○"
        }
    }

    /// agent 行可用性符号。
    public static func agentSymbol(available: Bool) -> String {
        available ? "●" : "？"
    }
}
/// 外观偏好 → SCUI ColorScheme 映射（跟随系统 → nil 不强制；
/// 成对文件：Sources/AgentKeeperUI/AppSettingsColorScheme.swift）。
public func linuxColorScheme(for mode: AppearanceMode) -> ColorScheme? {
    switch mode {
    case .system: nil
    case .light: .light
    case .dark: .dark
    }
}
#endif
