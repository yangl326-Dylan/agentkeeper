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
}
