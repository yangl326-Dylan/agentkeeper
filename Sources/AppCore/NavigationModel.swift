import Foundation
import DomainKit

/// 导航树分组大类（spec app-ui：全局 / agent 专属 / 项目三类组织）。
public enum NavigationSectionKind: Hashable, Sendable {
    case global
    case agent
    case project
}

/// 导航树分组。
public struct NavigationSection: Identifiable, Hashable {
    public var id: String { kind.slug + ":" + title }
    public var kind: NavigationSectionKind
    public var title: String
    public var count: Int
    public var skills: [Skill]
}

/// 三大类组织的分组构建（纯函数，UI 树单数据源）。
public enum NavigationModel {
    /// 规范顺序：全局（含 multiAgent 同铺设）→ agent 专属（按 agent 分）→ 项目（按项目名分）。
    public static func buildSections(skills: [Skill]) -> [NavigationSection] {
        var globalSkills: [Skill] = []
        var byAgent: [AgentID: [Skill]] = [:]
        var byProject: (titles: [String: [Skill]], roots: [String: ProjectRoot]) = ([:], [:])

        for skill in skills {
            switch skill.scope {
            case .global, .multiAgent:
                globalSkills.append(skill)
            case let .agentOnly(agentID):
                byAgent[agentID, default: []].append(skill)
            case let .project(agentID, root):
                _ = agentID  // 项目节按项目名聚合（跨 agent 同项目）
                byProject.titles[root.tagName, default: []].append(skill)
                byProject.roots[root.tagName] = root
            }
        }

        var sections: [NavigationSection] = [
            NavigationSection(kind: .global, title: "全局", count: globalSkills.count, skills: globalSkills),
        ]
        for agentID in byAgent.keys.sorted() {
            let list = byAgent[agentID] ?? []
            if list.isEmpty { continue }
            sections.append(NavigationSection(kind: .agent, title: agentID, count: list.count, skills: list))
        }
        for title in byProject.titles.keys.sorted() {
            let list = byProject.titles[title] ?? []
            if list.isEmpty { continue }
            sections.append(NavigationSection(kind: .project, title: title, count: list.count, skills: list))
        }
        // 空节不占位（空 catalog → 无节）
        if globalSkills.isEmpty {
            sections.removeFirst()
        }
        return sections
    }
}

private extension NavigationSectionKind {
    var slug: String {
        switch self {
        case .global: "global"
        case .agent: "agent"
        case .project: "project"
        }
    }
}
