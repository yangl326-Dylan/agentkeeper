import SwiftUI
import AppCore
import DomainKit

/// 三面板主壳：侧栏（导航）→ 内容（列表占位）→ 详情（占位）。
/// 本文件是骨架占位；真实视图在任务组 6 实现。
struct RootView: View {
    let store: AppStore

    var body: some View {
        NavigationSplitView {
            NavigationSidebar(store: store)
        } content: {
            NavigationContent(store: store)
        } detail: {
            NavigationDetail(store: store)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct NavigationSidebar: View {
    let store: AppStore

    var body: some View {
        List {
            Section("Agents") {
                if store.state.agents.isEmpty {
                    Label(
                        store.state.scan.phase == .running ? "正在扫描…" : "尚未扫描",
                        systemImage: store.state.scan.phase == .running ? "dot.radiowaves.left.and.right" : "tray"
                    )
                    .foregroundStyle(.secondary)
                }
                ForEach(store.state.agents) { agent in
                    Label(agentName(agent), systemImage: "externaldrive.badge.checkmark")
                        .foregroundStyle(isUnknown(agent) ? .secondary : .primary)
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        .navigationTitle("AgentKeeper")
    }

    private func agentName(_ agent: Agent) -> String {
        if case .unrecognizedStructure = agent.installState {
            return agent.name + "（结构未知）"
        }
        return agent.name
    }

    private func isUnknown(_ agent: Agent) -> Bool {
        if case .unrecognizedStructure = agent.installState { return true }
        return false
    }
}

struct NavigationContent: View {
    let store: AppStore

    var body: some View {
        List {
            Section("Skills") {
                Label("Skill 列表（占位）", systemImage: "square.grid.3x3")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("内容")
    }
}

struct NavigationDetail: View {
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("详情（占位）", systemImage: "doc.text.magnifyingglass")
            HStack(spacing: 8) {
                phaseDot
                Text(phaseText)
                    .font(.callout)
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .navigationTitle("详情")
    }

    @ViewBuilder private var phaseDot: some View {
        switch store.state.scan.phase {
        case .idle: Circle()
                .fill(.gray)
                .frame(width: 8, height: 8)
        case .running: Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
        case .complete: Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case .failed: Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
        }
    }

    private var phaseText: String {
        switch store.state.scan.phase {
        case .idle: "空闲"
        case .running: "扫描中"
        case .complete: "完成：\(store.state.scan.agentCount) agents"
        case .failed: "失败：\(store.state.scan.failureMessage ?? "未知")"
        }
    }
}
