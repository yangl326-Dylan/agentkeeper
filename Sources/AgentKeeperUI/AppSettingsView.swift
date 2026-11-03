import SwiftUI
import AppCore

/// 设置页（macOS SwiftUI 官方推荐：`Settings` 场景 + `Form`/`Section` 组织，
/// ⌘, 自动开启）。配置经 AppSettingsStore 落盘即时生效；文案经 env.l10n 双语。
@MainActor
public struct AppSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    public init() {}

    public var body: some View {
        let l = env.l10n
        Form {
            Section(l.settingsAppearance) {
                Picker(l.settingsTheme, selection: Binding(
                    get: { env.settings.appearance },
                    set: { env.settings.appearance = $0 }
                )) {
                    Text(l.settingsFollowSystem).tag(AppearanceMode.system)
                    Text(l.settingsLight).tag(AppearanceMode.light)
                    Text(l.settingsDark).tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section(l.settingsLanguage) {
                Picker(l.settingsLanguage, selection: Binding(
                    get: { env.settings.language },
                    set: { env.settings.language = $0 }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(l.settingsLanguageDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l.settingsMotion) {
                Picker(l.settingsReduceMotion, selection: Binding(
                    get: { env.settings.reduceMotionOverride },
                    set: { env.settings.reduceMotionOverride = $0 }
                )) {
                    Text(l.settingsFollowSystem).tag(Bool?.none)
                    Text(l.settingsAlwaysReduce).tag(Bool?.some(true))
                    Text(l.settingsAlwaysNormal).tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(l.settingsReduceMotionDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(l.settingsOnboardingSection) {
                Button(l.settingsShowOnboarding) {
                    env.firstRun.reset()
                    env.requestOnboarding()
                }
                Text(l.settingsOnboardingDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }
}
