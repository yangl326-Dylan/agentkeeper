import Foundation
import DomainKit
import AppCore

/// 导航选择切换（侧栏 Agents / Skills 节 / 标签共用）：点同项取消，点异项切换。
enum SelectionToggle {
    static func toggle<T: Equatable>(current: T?, clicked: T) -> T? {
        current == clicked ? nil : clicked
    }
}

/// Agent 筛选切换（兼容旧名，语义同 SelectionToggle）。
enum AgentSelection {
    static func toggle(current: AgentID?, clicked: AgentID) -> AgentID? {
        SelectionToggle.toggle(current: current, clicked: clicked)
    }
}

/// 侧栏 Skills 节 → 作用域筛选切换（点同节取消；全局节含同铺设）。
@MainActor
enum SectionSelection {
    static func kinds(for section: NavigationSection) -> Set<ScopeKind> {
        switch section.kind {
        case .global: return Set<ScopeKind>([.global, .multiAgent])
        case .project: return Set<ScopeKind>([.project])
        case .agent, .tag: return [] // agent→Agents 区；tag→tagSections（各自路径）
        }
    }

    static func toggle(current: Set<ScopeKind>, section: NavigationSection) -> Set<ScopeKind> {
        let kinds = kinds(for: section)
        return current == kinds ? [] : kinds
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
