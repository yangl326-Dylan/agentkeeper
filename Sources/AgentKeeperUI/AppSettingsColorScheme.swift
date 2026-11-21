// 外观偏好的 SwiftUI 映射（分栈）：Shared 只存偏好原始值，ColorScheme 构造留在各 UI 栈。
#if os(macOS)
import SwiftUI
import AgentKeeperShared

/// SwiftUI 强制色系；system → nil（不强制）。
extension AppearanceMode {
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 实际生效的强制色系（nil = 跟随系统）。
extension AppSettingsStore {
    public var effectiveColorScheme: ColorScheme? { appearance.colorScheme }
}
#endif
