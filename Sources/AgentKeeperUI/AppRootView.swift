import SwiftUI

/// 应用根视图：引导页 ↔ 主界面切换。
/// 状态收敛到 AppEnvironment（@Observable；曾用 App struct 级 @State——从 Window 内容
/// 写入不触发场景重评估，引导页卡死）。可见性有两路：首启由落盘标记决定；
/// 设置页「重新显示引导」→ requestOnboarding() 当次会话立即弹出。
@MainActor
public struct AppRootView: View {
    @Environment(AppEnvironment.self) private var env

    public init(initialHasCompleted: Bool) {}

    public var body: some View {
        Group {
            if env.isOnboardingVisible {
                OnboardingView(hasCompleted: Binding(
                    get: { !env.isOnboardingVisible },
                    set: { _ in env.completeOnboarding() }
                ))
            } else {
                RootView()
            }
        }
    }
}
