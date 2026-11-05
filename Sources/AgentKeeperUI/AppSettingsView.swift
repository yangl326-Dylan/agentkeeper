import SwiftUI
import AppKit
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

            Section(l.settingsAboutSection) {
                LabeledContent(l.settingsCurrentVersion) {
                    Text(env.updates.currentVersion.description)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                updateStatus(l)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }

    // MARK: - 更新状态

    @ViewBuilder
    private func updateStatus(_ l: L10n) -> some View {
        switch env.updates.state {
        case .idle:
            Button(l.settingsCheckForUpdates) {
                Task { await env.updates.check() }
            }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(l.settingsCheckingForUpdates)
                    .foregroundStyle(.secondary)
            }

        case let .upToDate(version):
            Label(l.settingsUpToDate(version.description), systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
            Button(l.settingsCheckForUpdates) {
                Task { await env.updates.check() }
            }

        case let .available(release):
            Label(l.settingsUpdateAvailable(release.version.description), systemImage: "arrow.down.circle")
            if env.updates.canInstallInPlace {
                if release.appAssetURL != nil {
                    Button(l.settingsUpdateNow) {
                        Task { await env.updates.install() }
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text(l.settingsNoAppAsset)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(l.settingsDevelopmentBuildHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(l.settingsOpenReleasePage) {
                NSWorkspace.shared.open(release.releaseURL)
            }

        case let .downloading(release):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(l.settingsDownloadingUpdate)
                    .foregroundStyle(.secondary)
            }
            Text(release.version.description)
                .font(.caption)
                .foregroundStyle(.secondary)

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(l.settingsInstallingUpdate)
                    .foregroundStyle(.secondary)
            }

        case let .failed(message):
            Label(l.settingsUpdateFailed, systemImage: "exclamationmark.triangle")
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Button(l.settingsCheckForUpdates) {
                    Task { await env.updates.check() }
                }
                Button(l.settingsOpenReleasePage) {
                    NSWorkspace.shared.open(env.updates.releasePageURL)
                }
            }
        }
    }
}
