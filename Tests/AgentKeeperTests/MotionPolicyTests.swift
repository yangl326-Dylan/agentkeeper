#if os(macOS)
import Testing
import AppCore
import AgentKeeperUI

/// MotionPolicy 单测（自 AppCoreTests 随 MotionPolicy 迁入——SwiftUI Animation 构造属 macOS UI 栈）。
@Suite struct MotionPolicyTests {
    @Test func normalSystemGivesSnappyMacosAnimations() {
        let policy = MotionPolicy(reduceMotion: false)
        #expect(policy.animation(for: .listTransition) != nil)
        #expect(policy.animation(for: .detailTransition) != nil)
        // 扫描呼吸态是装饰性动效：默认有
        #expect(policy.animation(for: .scanPulse) != nil)
    }

    @Test func reduceMotionDisablesAllDecorativeMotion() {
        let policy = MotionPolicy(reduceMotion: true)
        #expect(policy.animation(for: .listTransition) == nil)
        #expect(policy.animation(for: .detailTransition) == nil)
        #expect(policy.animation(for: .scanPulse) == nil)
    }
}

#endif
