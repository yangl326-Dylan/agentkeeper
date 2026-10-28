import Foundation
import DomainKit
import AppCore

/// Agent 筛选切换（点同项取消，点异项切换）。
enum AgentSelection {
    static func toggle(current: AgentID?, clicked: AgentID) -> AgentID? {
        current == clicked ? nil : clicked
    }
}

/// 侧栏 Agents 分组模型：只显示本机实际安装的 agent（目录存在），未安装不进侧栏。
@MainActor
enum SidebarAgentModel {
    enum Status: Equatable, Sendable {
        /// 已安装且结构可识别。
        case available
        /// 目录存在但结构未知（仍可见，提示排查）。
        case unrecognized
    }

    struct Row: Equatable, Identifiable, Sendable {
        let id: AgentID
        let name: String
        let status: Status
        let skillCount: Int

        var statusText: String {
            switch status {
            case .available: "可用 · \(skillCount) skills"
            case .unrecognized: "结构未知"
            }
        }
    }

    static func build(agents: [Agent], skills: [Skill]) -> [Row] {
        agents.compactMap { agent in
            let status: Status
            switch agent.installState {
            case .installed:
                status = .available
            case .unrecognizedStructure:
                status = .unrecognized
            case .notInstalled:
                return nil // 未安装：不进侧栏
            }
            let count = skills.filter { $0.owners.contains(agent.id) }.count
            return Row(
                id: agent.id,
                name: agent.name,
                status: status,
                skillCount: count
            )
        }
    }
}
