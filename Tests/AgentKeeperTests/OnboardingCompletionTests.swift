import Foundation
import Testing
import AppCore
@testable import AgentKeeperUI

/// 引导完成必须落盘（FirstRunStore）：App 级 @State 切换不可靠（SwiftUI 已知坑——
/// 从 Window 内容写 App struct 的 @State 不触发场景重评估，引导页卡死）。
/// 状态下沉到根 View + 持久化双保险：当次会话 View 级 @State 立即切换；
/// 跨启动由 FirstRunStore 保证完成过就不再出现。
@MainActor
@Suite struct OnboardingCompletionTests {
    @Test func completeOnboardingPersistsToDefaults() throws {
        let suite = "ak-test-onboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }

        let env = AppEnvironment(homeDirectory: home, defaults: defaults)
        #expect(!FirstRunStore(defaults: defaults).hasCompletedOnboarding)

        env.completeOnboarding()

        #expect(FirstRunStore(defaults: defaults).hasCompletedOnboarding)
    }

    @Test func completedDefaultsSkipOnboarding() throws {
        let suite = "ak-test-onboarding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // 完成过 → 初始不显示引导（AppRootView 判定输入）
        defaults.set(true, forKey: "hasCompletedOnboarding.v1")
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home, defaults: defaults)
        #expect(env.firstRun.hasCompletedOnboarding)
    }
}
