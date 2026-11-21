import Foundation
import DomainKit
import InfraKit

// MARK: - 动效类别（6.3）

/// 动效类别（时长与 easing 按 macOS 原生质感定制）。
/// SwiftUI `Animation` 构造在 UI 层（MotionPolicy，见 AgentKeeperUI/MotionPolicy.swift）——本类型保持平台无关。
public enum MotionCategory: Hashable, Sendable {
    /// 列表行插入/删除/移动（轻量淡入）；不该打扰。
    case listTransition
    /// 详情面板切换（spring/snappy 收束感）。
    case detailTransition
    /// 扫描进行中的呼吸态（纯装饰）。
    case scanPulse
}

// MARK: - 菜单栏摘要（6.4）

/// 菜单栏展示项。
public struct MenuAgentEntry: Hashable, Sendable, Identifiable {
    public var id: AgentID
    public var name: String
    public var skillCount: Int
    public var installed: Bool
}

/// 菜单栏摘要构建（agent 列表 + 各自 skill 数 + 总量）。
public struct MenuBarSummary: Hashable, Sendable {
    public var agentEntries: [MenuAgentEntry]
    public var totalSkills: Int

    public static func build(state: AppState, skills: [Skill]) -> MenuBarSummary {
        var counts: [AgentID: Int] = [:]
        for skill in skills {
            for owner in skill.owners {
                counts[owner, default: 0] += 1
            }
        }
        let entries = state.agents.map { agent in
            MenuAgentEntry(
                id: agent.id,
                name: agent.name,
                skillCount: counts[agent.id] ?? 0,
                installed: {
                    if case .installed = agent.installState { return true }
                    return false
                }()
            )
        }
        return MenuBarSummary(agentEntries: entries, totalSkills: skills.count)
    }
}

/// 菜单栏 agent 行的语义 SF Symbol（Raycast 式面板）。
/// 单一真相：`AgentSpec.icon`（内置与用户自定义一致）；未知 ID 回落 terminal。
public enum MenuBarIcons {
    public static func icon(
        for agentID: AgentID,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String {
        if let spec = BuiltInAgents.spec(for: agentID) {
            return spec.icon.isEmpty ? "terminal" : spec.icon
        }
        // 用户自定义 agent：图标来自 ~/.agentkeeper/agents.json
        let userConfig = UserAgentConfigLoader.load(
            baseDirectory: homeDirectory.appendingPathComponent(".agentkeeper", isDirectory: true)
        )
        if let spec = userConfig.specs.first(where: { $0.id == agentID }), !spec.icon.isEmpty {
            return spec.icon
        }
        return "terminal"
    }
}
