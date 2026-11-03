import Foundation
import AppCore
import SwiftUI

/// 外观模式：跟随系统 / 日间 / 夜间（默认跟随系统）。
@MainActor
public enum AppearanceMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// SwiftUI 强制色系；system → nil（不强制）。
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// 常见配置存储（UserDefaults 后端；macOS SwiftUI Settings 场景推荐做法——
/// 简单可序列化值 + 显式 key，跨启动持久、跨窗口共享）。
@MainActor
@Observable
public final class AppSettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let appearance = "appearance.v1"
        static let reduceMotion = "reduceMotion.v1"
        static let language = "language.v1"
    }

    /// 当前外观（写入即落盘）。
    public var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    /// 界面语言（i18n：system = 跟随系统首选语言；写入即落盘）。
    public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    /// 减弱动效覆盖：nil = 跟随系统（辅助功能偏好）；true/false 强制。
    public var reduceMotionOverride: Bool? {
        didSet {
            if let on = reduceMotionOverride {
                defaults.set(on ? 1 : 0, forKey: Key.reduceMotion)
            } else {
                defaults.removeObject(forKey: Key.reduceMotion)
            }
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        self.language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        // integer(forKey:) 对缺失 key 返回 0，必须先用 object 判存
        if defaults.object(forKey: Key.reduceMotion) == nil {
            self.reduceMotionOverride = nil
        } else {
            self.reduceMotionOverride = defaults.integer(forKey: Key.reduceMotion) == 1
        }
    }

    /// 实际生效的强制色系（nil = 跟随系统）。
    public var effectiveColorScheme: ColorScheme? { appearance.colorScheme }

    /// 实际生效的减弱动效（nil 覆盖 = 采辅助功能值）。
    public func effectiveReduceMotion(accessibility: Bool) -> Bool {
        reduceMotionOverride ?? accessibility
    }
}
