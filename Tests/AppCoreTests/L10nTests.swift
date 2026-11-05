import Foundation
import Testing
@testable import AppCore

/// i18n：语言解析 + 双语字符串表完整性（spec 2026-11-03 附加：设置可切换，默认同系统）。
@Suite struct L10nTests {
    @Test func systemLanguageResolvesChineseForZh() {
        #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-Hans-CN", "en"]) == .zhHans)
        #expect(AppLanguage.resolveSystem(preferredLanguages: ["zh-TW", "en"]) == .zhHans)
    }

    @Test func systemLanguageResolvesEnglishOtherwise() {
        #expect(AppLanguage.resolveSystem(preferredLanguages: ["en-US"]) == .english)
        #expect(AppLanguage.resolveSystem(preferredLanguages: ["ja-JP"]) == .english)
        #expect(AppLanguage.resolveSystem(preferredLanguages: []) == .english)
    }

    @Test func explicitLanguageOverridesSystem() {
        #expect(L10n.resolve(.english, preferredLanguages: ["zh-CN"]).lang == .english)
        #expect(L10n.resolve(.zhHans, preferredLanguages: ["en-US"]).lang == .zhHans)
        #expect(L10n.resolve(.system, preferredLanguages: ["zh-CN"]).lang == .zhHans)
    }

    /// 双语表完整性：抽查每个分组的键在两种语言下都非空且互不相同。
    @Test func allSurfacesNonEmptyInBothLanguages() {
        for lang in [ResolvedLanguage.zhHans, .english] {
            let l = L10n(lang: lang)
            for (name, value) in [
                ("sidebar.allSkills", l.sidebarAllSkills),
                ("sidebar.agents", l.sectionAgents),
                ("sidebar.scopes", l.sectionScopes),
                ("sidebar.global", l.scopeGlobal),
                ("sidebar.tags", l.sectionTags),
                ("sidebar.lifecycle", l.sectionLifecycle),
                ("list.noMatchingSkills", l.noMatchingSkills),
                ("list.searchPrompt", l.searchPrompt),
                ("common.scanNow", l.scanNow),
                ("common.cancel", l.commonCancel),
                ("common.install", l.commonInstall),
                ("strip.idle", l.stripIdle),
                ("strip.running", l.stripRunning),
                ("zone.disabledEmpty", l.zoneDisabledEmpty),
                ("zone.trashEmpty", l.zoneTrashEmpty),
                ("detail.preview", l.detailPreview),
                ("detail.history", l.detailHistory),
                ("detail.snapshots", l.detailSnapshots),
                ("onboarding.welcome", l.onboardingWelcome),
                ("onboarding.startScan", l.onboardingStartScan),
                ("settings.language", l.settingsLanguage),
                ("overview.title", l.overviewTitle),
            ] {
                #expect(!value.isEmpty, "\(name) (\(lang)) is empty")
            }
            #expect(l.sidebarAllSkills != L10n(lang: lang == .zhHans ? .english : .zhHans).sidebarAllSkills)
        }
    }

    /// 参数化文案：两种语言都拼入参数。
    @Test func parameterizedStringsCarryArguments() {
        let zh = L10n(lang: .zhHans)
        let en = L10n(lang: .english)
        #expect(zh.listTitleAgent("claude-code").contains("claude-code"))
        #expect(en.listTitleAgent("claude-code").contains("claude-code"))
        #expect(zh.zonePurgeMessage("/tmp/x").contains("/tmp/x"))
        #expect(en.zonePurgeMessage("/tmp/x").contains("/tmp/x"))
        #expect(en.scopeDetailText(.global(owners: ["a", "b"])).contains("a"))
    }

    /// 更新相关文案：双语非空、参数化正确、中英不同。
    @Test func updateStringsAreLocalized() {
        let zh = L10n(lang: .zhHans)
        let en = L10n(lang: .english)
        for l in [zh, en] {
            #expect(!l.settingsAboutSection.isEmpty)
            #expect(!l.settingsCurrentVersion.isEmpty)
            #expect(!l.settingsCheckForUpdates.isEmpty)
            #expect(!l.settingsUpdateNow.isEmpty)
            #expect(!l.settingsDownloadingUpdate.isEmpty)
            #expect(!l.settingsInstallingUpdate.isEmpty)
            #expect(!l.settingsUpdateFailed.isEmpty)
            #expect(!l.settingsOpenReleasePage.isEmpty)
            #expect(!l.settingsDevelopmentBuildHint.isEmpty)
            #expect(!l.settingsNoAppAsset.isEmpty)
        }
        #expect(zh.settingsUpToDate("0.3.0").contains("0.3.0"))
        #expect(en.settingsUpdateAvailable("0.3.0").contains("0.3.0"))
        #expect(zh.settingsUpdateNow != en.settingsUpdateNow)
    }
}
