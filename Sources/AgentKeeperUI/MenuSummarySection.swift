import SwiftUI
import AppKit
import AppCore

/// 菜单栏摘要面板（跨模块 public：可执行层 MenuBarExtra 直接装配）。
public struct MenuSummarySection: View {
    let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        let summary = MenuBarSummary.build(
            state: env.store.state,
            skills: env.catalogStore.current
        )
        // 摘要：只列本机实际安装的 agent（未安装的 harness 不占菜单行）
        Section {
            ForEach(summary.agentEntries.filter(\.installed)) { entry in
                HStack {
                    Image(systemName: entry.installed ? "checkmark.circle.fill" : "circle.slash")
                        .foregroundStyle(entry.installed ? Color.green : Color.secondary)
                    Text(entry.name)
                    Spacer()
                    Text("\(entry.skillCount) skills")
                        .foregroundStyle(.secondary)
                }
            }
            if summary.agentEntries.isEmpty {
                Text(env.store.state.scan.phase == .running ? "正在扫描…" : "尚未扫描")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text("Skill 总量 \(summary.totalSkills)")
                .font(.callout)
        }
        Divider()
        Button("打开主窗口") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button {
            Task {
                NSApplication.shared.activate(ignoringOtherApps: true)
                await env.scanNow()
            }
        } label: {
            if env.store.state.scan.phase == .running {
                HStack { Text("正在扫描…"); Spacer(); ProgressView().controlSize(.small) }
            } else {
                HStack { Text("立即扫描"); Spacer(); Image(systemName: "arrow.clockwise") }
            }
        }
        .disabled(env.store.state.scan.phase == .running)
        Divider()
        Button("退出 AgentKeeper") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
