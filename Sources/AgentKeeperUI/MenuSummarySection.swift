import SwiftUI
import AppKit
import DomainKit
import AppCore

/// 菜单栏摘要面板（Raycast 式三层迷你面板）。
/// 职责：摘要（状态橱窗）+ 快捷动作；完整管理仍在主窗口。
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
        let agents = summary.agentEntries.filter(\.installed)
        let isScanning = env.store.state.scan.phase == .running

        VStack(spacing: 0) {
            MenuBarHeaderRow(agentCount: agents.count, totalSkills: summary.totalSkills)

            if agents.isEmpty {
                Text(isScanning ? "正在扫描…" : "尚未发现已安装的 agent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(agents) { entry in
                    MenuBarAgentRow(
                        name: entry.name,
                        icon: MenuBarIcons.icon(for: entry.id),
                        skillCount: entry.skillCount,
                        targetDirectory: skillRootDirectory(for: entry.id)
                    )
                }
            }

            Divider().padding(.vertical, 6)

            MenuPanelActions(
                isScanning: isScanning,
                onOpenMain: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                },
                onScan: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    Task { await env.scanNow() }
                },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .frame(width: 260)
    }

    /// 该 agent 的第一个 skill 根目录（Finder 定位用；无则 nil，行不可点）。
    private func skillRootDirectory(for agentID: AgentID) -> URL? {
        env.store.state.agents
            .first(where: { $0.id == agentID })?
            .skillRoots.first?.path
    }
}
