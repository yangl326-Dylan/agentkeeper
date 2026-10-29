import Foundation
import SwiftUI
import Testing
@testable import AgentKeeperUI

/// 外观偏好（跟随系统/日间/夜间）——默认值、映射与 UserDefaults 持久化。
@MainActor
@Suite struct AppSettingsStoreTests {
    @Test func defaultsFollowSystem() {
        let defaults = UserDefaults(suiteName: "ak-settings-test-\(UUID().uuidString)")!
        let store = AppSettingsStore(defaults: defaults)
        #expect(store.appearance == .system)
        #expect(store.effectiveColorScheme == nil) // 跟随系统 → 不强制
        #expect(store.reduceMotionOverride == nil)
    }

    @Test func explicitSchemeMapsAndPersists() {
        let name = "ak-settings-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = AppSettingsStore(defaults: defaults)
        store.appearance = .dark
        #expect(store.effectiveColorScheme == .dark)
        // 新实例读同库 → 持久化生效
        let reloaded = AppSettingsStore(defaults: UserDefaults(suiteName: name)!)
        #expect(reloaded.appearance == .dark)
        #expect(reloaded.effectiveColorScheme == .dark)

        store.appearance = .light
        #expect(store.effectiveColorScheme == .light)
    }

    @Test func reduceMotionOverrideBeatsAccessibility() {
        let defaults = UserDefaults(suiteName: "ak-settings-test-\(UUID().uuidString)")!
        let store = AppSettingsStore(defaults: defaults)
        // 跟随系统：直接采用辅助功能值
        #expect(store.effectiveReduceMotion(accessibility: false) == false)
        #expect(store.effectiveReduceMotion(accessibility: true) == true)
        // 显式覆盖
        store.reduceMotionOverride = true
        #expect(store.effectiveReduceMotion(accessibility: false) == true)
        store.reduceMotionOverride = false
        #expect(store.effectiveReduceMotion(accessibility: true) == false)
    }

    @Test func persistenceOfReduceMotionOverride() {
        let name = "ak-settings-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = AppSettingsStore(defaults: defaults)
        store.reduceMotionOverride = true
        let reloaded = AppSettingsStore(defaults: UserDefaults(suiteName: name)!)
        #expect(reloaded.reduceMotionOverride == true)
    }
}
