import Foundation
import DomainKit

/// 导航树分组大类（spec app-ui：全局 / agent 专属 / 项目三类组织；Phase 2：标签）。
public enum NavigationSectionKind: Hashable, Sendable {
    case global
    case agent
    case project
    case tag
}

/// 导航树分组。
public struct NavigationSection: Identifiable, Hashable {
    public var id: String { kind.slug + ":" + title }
    public var kind: NavigationSectionKind
    public var title: String
    public var count: Int
    public var skills: [Skill]

    public init(kind: NavigationSectionKind, title: String, count: Int, skills: [Skill]) {
        self.kind = kind
        self.title = title
        self.count = count
        self.skills = skills
    }
}

/// 三大类组织的分组构建（纯函数，UI 树单数据源）。
public enum NavigationModel {
    /// 规范顺序：全局（含 multiAgent 同铺设）→ 项目（按项目名分）。
    /// agent 专属不产出分组——agent 维度由侧栏 Agents 区承担（点击筛选），
    /// 此处再按 agent 分组即重复且旧按钮无筛选作用。
    public static func buildSections(skills: [Skill]) -> [NavigationSection] {
        var globalSkills: [Skill] = []
        var byProject: (titles: [String: [Skill]], roots: [String: ProjectRoot]) = ([:], [:])

        for skill in skills {
            switch skill.scope {
            case .global, .multiAgent:
                globalSkills.append(skill)
            case .agentOnly:
                break // Agents 区维度，不进 Skills 区
            case let .project(agentID, root):
                _ = agentID  // 项目节按项目名聚合（跨 agent 同项目）
                byProject.titles[root.tagName, default: []].append(skill)
                byProject.roots[root.tagName] = root
            }
        }

        var sections: [NavigationSection] = []
        if !globalSkills.isEmpty {
            sections.append(NavigationSection(kind: .global, title: "全局", count: globalSkills.count, skills: globalSkills))
        }
        for title in byProject.titles.keys.sorted() {
            let list = byProject.titles[title] ?? []
            if list.isEmpty { continue }
            sections.append(NavigationSection(kind: .project, title: title, count: list.count, skills: list))
        }
        return sections
    }

    /// 标签节构建（Phase 2）：按标签名分组，count = 携带该标签的 skill 数。
    /// catalog 无条目的标签不渲染（与三分类节的空节语义一致）。
    public static func buildTagSections(
        skills: [Skill],
        tagsBySkill: [String: [String]]
    ) -> [NavigationSection] {
        var byTag: [String: [Skill]] = [:]
        for skill in skills {
            for tag in tagsBySkill[skill.id] ?? [] {
                byTag[tag, default: []].append(skill)
            }
        }
        return byTag.keys.sorted().compactMap { tag -> NavigationSection? in
            let list = byTag[tag] ?? []
            guard !list.isEmpty else { return nil }
            return NavigationSection(kind: .tag, title: tag, count: list.count, skills: list)
        }
    }
}

private extension NavigationSectionKind {
    var slug: String {
        switch self {
        case .global: "global"
        case .agent: "agent"
        case .project: "project"
        case .tag: "tag"
        }
    }
}
