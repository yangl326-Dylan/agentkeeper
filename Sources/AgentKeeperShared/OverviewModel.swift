import Foundation
import AppCore
import DomainKit

/// 总览模型（MangoDisk 式扫描仪表盘）：未选中 skill 时的主界面数据底座。
/// （共享展示层：build 纯聚合逻辑双栈共用，视图分栈渲染。）
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
