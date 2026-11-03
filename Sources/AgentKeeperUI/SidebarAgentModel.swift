import Foundation
import DomainKit
import AppCore

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
        // statusText 已收敛到 L10n.agentRowStatus（i18n）
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
