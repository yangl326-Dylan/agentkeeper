import Foundation
import Testing
@testable import AppCore

@Suite struct FirstRunStoreTests {
    @Test func freshInstanceShowsOnboardingOnce() {
        let suite = "ak-test-\(UUID().uuidString)"
        var store = FirstRunStore(defaults: UserDefaults(suiteName: suite)!)
        #expect(store.hasCompletedOnboarding == false)

        store.completeOnboarding()
        #expect(store.hasCompletedOnboarding)
    }

    @Test func onboardingCompletionPersistsAcrossInstances() {
        let suite = "ak-test-\(UUID().uuidString)"
        do {
            var store = FirstRunStore(defaults: UserDefaults(suiteName: suite)!)
            store.completeOnboarding()
        }
        // 模拟应用重启
        let reloaded = FirstRunStore(defaults: UserDefaults(suiteName: suite)!)
        #expect(reloaded.hasCompletedOnboarding)
    }
}
