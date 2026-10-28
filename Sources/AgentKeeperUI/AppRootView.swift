import SwiftUI

/// 应用根视图：引导页 ↔ 主界面切换。
/// 状态必须放在 View 级 @State（App struct 的 @State 从 Window 内容写入不会可靠触发
/// 场景重评估——SwiftUI 已知坑，曾导致引导页卡死）；完成态经 FirstRunStore 落盘，
/// 跨启动由 env.firstRun 决定初始值（完成过直接进主界面）。
@MainActor
public struct AppRootView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var hasCompletedOnboarding: Bool

    public init(initialHasCompleted: Bool) {
        _hasCompletedOnboarding = State(initialValue: initialHasCompleted)
    }

    public var body: some View {
        Group {
            if hasCompletedOnboarding {
                RootView()
            } else {
                OnboardingView(hasCompleted: $hasCompletedOnboarding)
            }
        }
        // 完成即落盘：即使当次会话状态异常，下次启动也不再弹引导
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed { env.completeOnboarding() }
        }
    }
}
