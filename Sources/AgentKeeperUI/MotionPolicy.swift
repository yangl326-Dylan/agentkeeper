#if os(macOS)
import SwiftUI
import AppCore

/// 动效策略：系统「减少动态效果」开启时全部返回 nil（即时切换，保留状态语义）。
/// 平台注记：本类型属 macOS UI 栈（SwiftUI Animation）；Linux 栈（add-linux-app）将以 GTK 质感实现同等策略。
public struct MotionPolicy: Hashable, Sendable {
    public var reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    /// 对应类别的 Animation；nil 表示不动画（即时呈现）。
    public func animation(for category: MotionCategory) -> Animation? {
        guard !reduceMotion else { return nil }
        switch category {
        case .listTransition:
            return Animation.snappy(duration: 0.22)
        case .detailTransition:
            return Animation.snappy(duration: 0.3)
        case .scanPulse:
            return Animation.easeInOut(duration: 1.2)
        }
    }
}

#endif
