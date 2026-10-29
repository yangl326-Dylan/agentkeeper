import SwiftUI

/// 设置页（macOS SwiftUI 官方推荐：`Settings` 场景 + `Form`/`Section` 组织，
/// ⌘, 自动开启）。配置经 AppSettingsStore 落盘即时生效。
@MainActor
public struct AppSettingsView: View {
    @Environment(AppEnvironment.self) private var env

    public init() {}

    public var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: Binding(
                    get: { env.settings.appearance },
                    set: { env.settings.appearance = $0 }
                )) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("动效") {
                Picker("减弱动效", selection: Binding(
                    get: { env.settings.reduceMotionOverride },
                    set: { env.settings.reduceMotionOverride = $0 }
                )) {
                    Text("跟随系统").tag(Bool?.none)
                    Text("始终减弱").tag(Bool?.some(true))
                    Text("始终正常").tag(Bool?.some(false))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text("减弱后列表过渡、详情切换等动画即时呈现。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("引导") {
                Button("重新显示首次引导页") {
                    env.firstRun.reset()
                    env.requestOnboarding()
                }
                Text("重新打开 AgentKeeper 首次启动时的功能引导。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 480)
    }
}
