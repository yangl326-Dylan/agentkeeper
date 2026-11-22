#if os(Linux)
import SwiftCrossUI
import AgentKeeperShared
import AppCore

/// 设置窗口内容（SCUI 无 Settings 场景 → 独立 Window 承载，报告 §4.3 映射结论）。
/// 语言/主题/动效走同一 AppSettingsStore（写入即落盘即时生效，与 macOS 同语义）；
/// 更新检查：UpdateModel 平台无关直用——available 状态展示版本并跳 Release 页
/// （Linux 不支持原地安装：UnsupportedAppInstaller 兜底，仅检查 + 跳转）。
/// 成对文件：Sources/AgentKeeperUI/AppSettingsView.swift。
public struct LinuxSettingsView: View {
    public let env: AppEnvironment

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        let l = env.l10n
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // MARK: 主题
                Text(l.settingsAppearance)
                    .font(.headline)
                    .foregroundColor(LinuxPalette.textPrimary)
                LinuxSegmentedChoice(
                    options: appearanceOptions,
                    selection: env.settings.appearance,
                    onSelect: { env.settings.appearance = $0 }
                )

                // MARK: 语言（即时生效：env.l10n 由 settings.language 驱动）
                Text(l.settingsLanguage)
                    .font(.headline)
                    .foregroundColor(LinuxPalette.textPrimary)
                LinuxSegmentedChoice(
                    options: languageOptions,
                    selection: env.settings.language,
                    onSelect: { env.settings.language = $0 }
                )
                Text(l.settingsLanguageDetail)
                    .font(.caption)
                    .foregroundColor(LinuxPalette.textSecondary)

                // MARK: 动效（减弱动效覆盖：跟随系统/始终减弱/始终正常）
                Text(l.settingsMotion)
                    .font(.headline)
                    .foregroundColor(LinuxPalette.textPrimary)
                LinuxSegmentedChoice(
                    options: motionOptions,
                    selection: env.settings.reduceMotionOverride,
                    onSelect: { env.settings.reduceMotionOverride = $0 }
                )
                Text(l.settingsReduceMotionDetail)
                    .font(.caption)
                    .foregroundColor(LinuxPalette.textSecondary)

                Divider()

                // MARK: 关于与更新
                Text(l.settingsAboutSection)
                    .font(.headline)
                    .foregroundColor(LinuxPalette.textPrimary)
                HStack(spacing: 8) {
                    Text(l.settingsCurrentVersion)
                        .font(.body)
                        .foregroundColor(LinuxPalette.textSecondary)
                    Text(env.updates.currentVersion.description)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(LinuxPalette.textPrimary)
                }
                updateStatus
            }
            .padding(20)
            .frame(maxWidth: 420, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinuxPalette.background)
    }

    // MARK: 选项构造（选项 label 随界面语言在渲染期重建，语言切换即刷新）

    private var appearanceOptions: [LinuxChoiceOption<AppearanceMode>] {
        let l = env.l10n
        return [
            LinuxChoiceOption(value: .system, label: l.settingsFollowSystem),
            LinuxChoiceOption(value: .light, label: l.settingsLight),
            LinuxChoiceOption(value: .dark, label: l.settingsDark),
        ]
    }

    private var languageOptions: [LinuxChoiceOption<AppLanguage>] {
        AppLanguage.allCases.map { LinuxChoiceOption(value: $0, label: $0.displayName) }
    }

    private var motionOptions: [LinuxChoiceOption<Bool?>] {
        let l = env.l10n
        return [
            LinuxChoiceOption(value: nil, label: l.settingsFollowSystem),
            LinuxChoiceOption(value: true, label: l.settingsAlwaysReduce),
            LinuxChoiceOption(value: false, label: l.settingsAlwaysNormal),
        ]
    }

    // MARK: 更新状态（对齐 macOS AppSettingsView.updateStatus 的状态机呈现）

    @ViewBuilder
    private var updateStatus: some View {
        let l = env.l10n
        switch env.updates.state {
        case .idle:
            Button(l.settingsCheckForUpdates) {
                Task { await env.updates.check() }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                    .frame(width: 12, height: 12)
                Text(l.settingsCheckingForUpdates)
                    .foregroundColor(LinuxPalette.textSecondary)
            }

        case let .upToDate(version):
            Text("● " + l.settingsUpToDate(version.description))
                .font(.caption)
                .foregroundColor(LinuxPalette.green)
            Button(l.settingsCheckForUpdates) {
                Task { await env.updates.check() }
            }

        case let .available(release):
            // Linux 不做原地安装：展示版本 + 打开 Release 页（UnsupportedAppInstaller 兜底语义）
            Text("▲ " + l.settingsUpdateAvailable(release.version.description))
                .font(.body)
                .foregroundColor(LinuxPalette.amber)
            Text(l.settingsDevelopmentBuildHint)
                .font(.caption)
                .foregroundColor(LinuxPalette.textSecondary)
            Button(l.settingsOpenReleasePage) {
                env.adapter.openURL(release.releaseURL)
            }

        case .downloading:
            Text(l.settingsDownloadingUpdate)
                .foregroundColor(LinuxPalette.textSecondary)

        case .installing:
            Text(l.settingsInstallingUpdate)
                .foregroundColor(LinuxPalette.textSecondary)

        case let .failed(message):
            Text("▲ " + l.settingsUpdateFailed)
                .font(.caption)
                .foregroundColor(LinuxPalette.red)
            Text(message)
                .font(.caption)
                .foregroundColor(LinuxPalette.textSecondary)
            HStack(spacing: 8) {
                Button(l.settingsCheckForUpdates) {
                    Task { await env.updates.check() }
                }
                Button(l.settingsOpenReleasePage) {
                    env.adapter.openURL(env.updates.releasePageURL)
                }
            }
        }
    }
}
#endif
