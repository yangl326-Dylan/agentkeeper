import Foundation
import DomainKit

// MARK: - 生命周期分区（侧栏「生命周期」选择；目录常驻，节点恒有效）

public enum LifecycleZone: String, Equatable, Sendable, CaseIterable {
    case disabled
    case trash

    /// 侧栏/导航图标（SF Symbols）。
    public var symbol: String {
        switch self {
        case .disabled: "pause.circle"
        case .trash: "trash"
        }
    }

    /// 本地化标题（i18n）。
    public func title(_ l10n: L10n) -> String { l10n.zoneTitle(self) }
}

// MARK: - 侧栏节点（导航视图：全侧栏单选）

/// 侧栏单选节点：某一时刻只看一个视角；列表 = 节点集合 ∩ 搜索词。
public enum SidebarNode: Hashable, Sendable {
    /// 「所有 Skills」根节点（默认选中，count = catalog 总数）。
    case all
    case agent(AgentID)
    /// 全局（global + multiAgent，与 buildSections「全局」节口径一致）。
    case global
    case project(String)
    case tag(String)
    case zone(LifecycleZone)
}

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
        var byTag: [String: [String]] = [:]
        var counts: [String: Int] = [:]
        for skill in skills {
            for tag in tagsBySkill[skill.id] ?? [] {
                byTag[tag, default: []].append(skill.id)
                counts[tag, default: 0] += 1
            }
        }
        return byTag.keys.sorted().compactMap { tag -> NavigationSection? in
            guard let count = counts[tag], count > 0 else { return nil }
            return NavigationSection(kind: .tag, title: tag, count: count, skills: [])
        }
    }

    // MARK: 侧栏节点 → 查询（纯函数：视图 ∩ 搜索的组合语义唯一收口）

    /// 节点对应的 catalog 查询；生命周期区不走 catalog（UI 切换为区视图）→ nil。
    public static func catalogQuery(for node: SidebarNode) -> CatalogQuery? {
        var query = CatalogQuery.initial
        switch node {
        case .all:
            break
        case let .agent(agentID):
            query.agentID = agentID
        case .global:
            query.scopeKinds = [.global, .multiAgent]
        case let .project(name):
            query.scopeKinds = [.project]
            query.projectName = name
        case let .tag(tag):
            query.tag = tag
        case .zone:
            return nil
        }
        return query
    }

    /// 列表导航标题（视图名进标题，替代已移除的工具条筛选菜单；i18n）。
    public static func listTitle(for node: SidebarNode, l10n: L10n) -> String {
        switch node {
        case .all: l10n.listTitleAll
        case .global: l10n.listTitleGlobal
        case let .agent(id): l10n.listTitleAgent(id)
        case let .project(name): l10n.listTitleProject(name)
        case let .tag(tag): l10n.listTitleTag(tag)
        case let .zone(zone): zone.title(l10n)
        }
    }

    /// 节点失效归一：节点背后的集合消失（agent 卸载 / 项目或标签清空 / 全局节为空）→ 回落 .all。
    /// 扫描重建 catalog 后由 UI 层调用，按节点标识匹配（不按 index），保持选中稳定。
    public static func normalize(
        node: SidebarNode,
        sections: [NavigationSection],
        tagTitles: [String],
        installedAgentIDs: [AgentID]
    ) -> SidebarNode {
        switch node {
        case .all, .zone:
            return node // .all 恒有效；zone 目录常驻
        case let .agent(agentID):
            return installedAgentIDs.contains(agentID) ? node : .all
        case .global:
            return sections.contains { $0.kind == .global } ? node : .all
        case let .project(name):
            return sections.contains { $0.kind == .project && $0.title == name } ? node : .all
        case let .tag(tag):
            return tagTitles.contains(tag) ? node : .all
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
