import Foundation
import SwiftUI
import Testing
import AppCore
@testable import AgentKeeperUI

/// 外观偏好（跟随系统/日间/夜间）——默认值、映射与 UserDefaults 持久化。
@MainActor
@Suite struct AppSettingsStoreTests {
    @Test func defaultsFollowSystem() {
        let defaults = UserDefaults(suiteName: "ak-settings-test-\(UUID().uuidString)")!
        let store = AppSettingsStore(defaults: defaults)
        #expect(store.appearance == .system)
        #expect(store.language == .system) // i18n：默认同系统语言
        #expect(store.effectiveColorScheme == nil) // 跟随系统 → 不强制
        #expect(store.reduceMotionOverride == nil)
    }

    /// 语言设置持久化（i18n：设置切换跨启动生效）。
    @Test func languagePersists() {
        let name = "ak-settings-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = AppSettingsStore(defaults: defaults)
        store.language = .english
        let reloaded = AppSettingsStore(defaults: UserDefaults(suiteName: name)!)
        #expect(reloaded.language == .english)
        // 跟随系统按首选语言解析（zh* → 中文）
        #expect(L10n.resolve(.system, preferredLanguages: ["zh-Hans-CN"]).lang == .zhHans)
        #expect(L10n.resolve(reloaded.language, preferredLanguages: ["zh-Hans-CN"]).lang == .english)
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
