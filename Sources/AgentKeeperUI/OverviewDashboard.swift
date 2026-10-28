import Foundation
import SwiftUI
import AppCore
import DomainKit

/// 总览模型（MangoDisk 式扫描仪表盘）：未选中 skill 时的主界面数据底座。
public struct OverviewModel: Equatable, Sendable {
    public struct AgentEntry: Equatable, Identifiable, Sendable {
        public let id: AgentID
        public let skillCount: Int
    }

    public let totalSkills: Int
    public let installedAgents: Int
    public let agentEntries: [AgentEntry]
    public let scopeCounts: [ScopeKind: Int]
    public let tagCount: Int
    public let lastScanAt: Date?

    public static func build(state: AppState, skills: [Skill], tagCount: Int) -> OverviewModel {
        // agent 维度：安装态的 agent 各自可用 skill 数（专属/项目 + 全局共享——agent 可加载全局 skill）
        let installed = state.agents.filter {
            if case .installed = $0.installState { return true }
            return false
        }
        let entries = installed.map { agent in
            OverviewModel.AgentEntry(
                id: agent.id,
                skillCount: skills.filter { $0.owners.contains(agent.id) }.count
            )
        }
        var scopes: [ScopeKind: Int] = [:]
        for skill in skills {
            scopes[ScopeKind.of(skill), default: 0] += 1
        }
        return OverviewModel(
            totalSkills: skills.count,
            installedAgents: installed.count,
            agentEntries: entries,
            scopeCounts: scopes,
            tagCount: tagCount,
            lastScanAt: state.scan.lastCompletedAt
        )
    }
}

/// 总览仪表盘（MangoDisk 式扫描产出全貌：统计卡 + 作用域分布 + agent 卡片）。
@MainActor
public struct OverviewDashboard: View {
    @Environment(AppEnvironment.self) private var env

    public init() {}

    public var body: some View {
        ScrollView {
            OverviewContent()
        }
    }
}

/// 仪表盘正文（独立 View 节点：@Environment 在渲染期解析；
/// ScrollView 离屏渲染空白，快照直接引用本节点）。
@MainActor
struct OverviewContent: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        let model = OverviewModel.build(
            state: env.store.state,
            skills: env.catalogStore.current,
            tagCount: env.tagService.tags().count
        )
        return VStack(alignment: .leading, spacing: 20) {
            header(model)
            statCards(model)
            scopeSection(model)
            agentsSection(model)
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func header(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("总览", systemImage: "shippingbox.and.arrow.backward.fill")
                .font(.title2.bold())
            if let at = model.lastScanAt {
                Text("上次扫描 \(OverviewDashboard.clockText(at))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("尚未扫描——点击工具栏「立即扫描」开始")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statCards(_ model: OverviewModel) -> some View {
        HStack(spacing: 14) {
            statCard(value: model.totalSkills, label: "Skills", icon: "square.stack.3d.up")
            statCard(value: model.installedAgents, label: "Agents", icon: "externaldrive.badge.checkmark")
            statCard(value: model.tagCount, label: "标签", icon: "tag")
        }
    }

    private func statCard(value: Int, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(ClaudePalette.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private func scopeSection(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("作用域分布", systemImage: "scope")
                .font(.headline)
            let total = max(model.totalSkills, 1)
            ForEach([ScopeKind.global, .agentOnly, .project, .multiAgent], id: \.self) { kind in
                let count = model.scopeCounts[kind] ?? 0
                HStack(spacing: 10) {
                    Text(kind.label)
                        .font(.callout)
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary.opacity(0.4))
                            Capsule()
                                .fill(ClaudePalette.accent)
                                .frame(width: proxy.size.width * CGFloat(count) / CGFloat(total))
                        }
                    }
                    .frame(height: 8)
                    Text("\(count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }

    private func agentsSection(_ model: OverviewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Agents", systemImage: "person.crop.square")
                .font(.headline)
            if model.agentEntries.isEmpty {
                Text("尚未发现已安装 agent——安装 Claude Code / Codex 等后自动识别")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.agentEntries) { entry in
                    HStack {
                        Image(systemName: "externaldrive.badge.checkmark")
                            .foregroundStyle(ClaudePalette.accent)
                        Text(entry.id)
                        Spacer()
                        Text("\(entry.skillCount) skills")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

extension OverviewDashboard {
    static func clockText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

extension ScopeKind {
    var label: String {
        switch self {
        case .global: "全局"
        case .agentOnly: "Agent 专属"
        case .project: "项目级"
        case .multiAgent: "同铺设"
        }
    }
}
