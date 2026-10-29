import Foundation

/// 首启引导状态（6.6）：完成一次引导后不再出现。
public struct FirstRunStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let key = "hasCompletedOnboarding.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var hasCompletedOnboarding: Bool {
        defaults.bool(forKey: Self.key)
    }

    public mutating func completeOnboarding() {
        defaults.set(true, forKey: Self.key)
    }

    /// 设置页「重新显示引导页」配套：清除落盘完成标记（下次启动也会再出引导）。
    public mutating func reset() {
        defaults.removeObject(forKey: Self.key)
    }
}
