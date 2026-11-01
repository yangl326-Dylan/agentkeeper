import Foundation
import SwiftUI
import DomainKit

// MARK: - 动效策略（6.3）

/// 动效类别（时长与 easing 按 macOS 原生质感定制）。
public enum MotionCategory: Hashable, Sendable {
    /// 列表行插入/删除/移动（轻量淡入）；不该打扰。
    case listTransition
    /// 详情面板切换（spring/snappy 收束感）。
    case detailTransition
    /// 扫描进行中的呼吸态（纯装饰）。
    case scanPulse
}

/// 动效策略：系统「减少动态效果」开启时全部返回 nil（即时切换，保留状态语义）。
public struct MotionPolicy: Hashable, Sendable {
    public var reduceMotion: Bool

    public init(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }

    /// 对应类别的 Animation；nil 表示不动画（即时呈现）。
    public func animation(for category: MotionCategory) -> Animation? {
        guard !reduceMotion else { return nil }
        switch category {
        case .listTransition:
            return Animation.snappy(duration: 0.22)
        case .detailTransition:
            return Animation.snappy(duration: 0.3)
        case .scanPulse:
            return Animation.easeInOut(duration: 1.2)
        }
    }
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

/// 菜单栏 agent 行的语义 SF Symbol（Raycast 式面板）。未知 ID 统一回落 terminal。
public enum MenuBarIcons {
    private static let mapping: [AgentID: String] = [
        "claude-code": "chevron.left.forwardslash.chevron.right",
        "opencode": "chevron.left.forwardslash.chevron.right",
        "codex": "chevron.left.forwardslash.chevron.right",
        "cursor": "cursorarrow.rays",
        "gemini": "sparkles",
        "qwen": "sparkles",
        "pi": "terminal",
        "oh-my-pi": "terminal",
        "openclaw": "terminal",
        "agents-shared": "person.2",
    ]

    public static func icon(for agentID: AgentID) -> String {
        mapping[agentID] ?? "terminal"
    }
}
