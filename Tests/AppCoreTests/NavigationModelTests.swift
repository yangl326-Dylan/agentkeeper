import Foundation
import Testing
import DomainKit
@testable import AppCore

@Suite struct NavigationModelTests {
    private func skill(_ name: String, scope: SkillScope) -> Skill {
        Skill(
            id: "\(name)|test",
            name: name,
            directory: URL(fileURLWithPath: "/tmp/x/\(name)"),
            scope: scope,
            sha256: "s-\(name)",
            skillDescription: "desc"
        )
    }

    /// Skills 区只保留作用域维度（全局/项目）——agent 维度由侧栏 Agents 区承担（可点击筛选），
    /// 不再产出 .agent 分组（曾与 Agents 区重复且按钮无筛选作用）。
    @Test func scopeSectionsWithoutAgentDuplication() {
        let sections = NavigationModel.buildSections(skills: [
            skill("proj-skill", scope: .project(agentID: "claude-code", root: ProjectRoot(path: "/users/x/code/atlas"))),
            skill("only-pi", scope: .agentOnly(agentID: "pi")),
            skill("shared", scope: .global(owners: ["claude-code", "pi"])),
        ])
        #expect(sections.map({ $0.kind }) == [.global, .project])
        #expect(sections[0].title == "全局")
        #expect(sections[1].title == "atlas")
    }

    @Test func projectSkillsGroupByProjectNameWithCounts() {
        let atlas = ProjectRoot(path: "/users/x/code/atlas")
        let beta = ProjectRoot(path: "/users/x/code/beta")
        let sections = NavigationModel.buildSections(skills: [
            skill("deploy", scope: .project(agentID: "claude-code", root: atlas)),
            skill("lint", scope: .project(agentID: "opencode", root: atlas)),
            skill("orbit", scope: .project(agentID: "claude-code", root: beta)),
        ])
        let projects = sections.filter { $0.kind == .project }
        #expect(projects.count == 2)
        let atlasSection = projects.first { $0.title == "atlas" }
        #expect(atlasSection?.count == 2)
        #expect(projects.first { $0.title == "beta" }?.count == 1)
    }

    @Test func multiAgentSkillsLandInGlobalSection() {
        let sections = NavigationModel.buildSections(skills: [
            skill("twin-a", scope: .multiAgent(["claude-code", "opencode"])),
        ])
        #expect(sections.count == 1)
        #expect(sections[0].kind == .global)
        #expect(sections[0].count == 1)
    }

    @Test func emptyCatalogProducesNoSections() {
        #expect(NavigationModel.buildSections(skills: []).isEmpty)
    }

    /// agent 专属 skill 不进 Skills 区（经 Agents 区点击进入）——纯 agentOnly catalog 无节。
    @Test func agentOnlySkillsYieldNoSections() {
        let sections = NavigationModel.buildSections(skills: [
            skill("a", scope: .agentOnly(agentID: "opencode")),
            skill("b", scope: .agentOnly(agentID: "opencode")),
            skill("c", scope: .agentOnly(agentID: "claude-code")),
        ])
        #expect(sections.isEmpty)
    }
}

// MARK: - SidebarNode → CatalogQuery 映射（侧栏导航视图：单选节点 + 搜索 AND 叠加）

@Suite struct SidebarNodeQueryTests {
    private func skill(_ name: String, scope: SkillScope) -> Skill {
        Skill(
            id: "\(name)|test",
            name: name,
            directory: URL(fileURLWithPath: "/tmp/x/\(name)"),
            scope: scope,
            sha256: "s-\(name)",
            skillDescription: "desc"
        )
    }

    private var catalog: [Skill] {
        [
            skill("only", scope: .agentOnly(agentID: "pi")),
            skill("shared", scope: .global(owners: ["claude-code"])),
            skill("twin", scope: .multiAgent(["claude-code", "opencode"])),
            skill("deploy", scope: .project(agentID: "claude-code", root: ProjectRoot(path: "/users/x/code/atlas"))),
        ]
    }

    @Test func allNodeAppliesNoFilters() {
        let query = NavigationModel.catalogQuery(for: .all)!
        #expect(query.apply(catalog: catalog).count == 4)
    }

    @Test func agentNodeFiltersByOwners() {
        let query = NavigationModel.catalogQuery(for: .agent("pi"))!
        #expect(query.apply(catalog: catalog).map(\.name) == ["only"])
    }

    /// 全局节点含 global + multiAgent（与 buildSections 的「全局」节口径一致）。
    @Test func globalNodeIncludesGlobalAndMultiAgent() {
        let query = NavigationModel.catalogQuery(for: .global)!
        #expect(Set(query.apply(catalog: catalog).map(\.name)) == ["shared", "twin"])
    }

    /// 项目节点按项目名过滤（旧实现只按 [.project] 大类——所有项目混在一起）。
    @Test func projectNodeFiltersByProjectName() {
        let query = NavigationModel.catalogQuery(for: .project("atlas"))!
        #expect(query.apply(catalog: catalog).map(\.name) == ["deploy"])
    }

    @Test func tagNodeCarriesTag() {
        let query = NavigationModel.catalogQuery(for: .tag("distribution"))!
        #expect(query.tag == "distribution")
    }

    /// 生命周期区不走 catalog 查询（UI 切换为区视图）。
    @Test func zoneNodeYieldsNilQuery() {
        #expect(NavigationModel.catalogQuery(for: .zone(.disabled)) == nil)
        #expect(NavigationModel.catalogQuery(for: .zone(.trash)) == nil)
    }

    /// 搜索词独立叠加（AND）。
    @Test func searchCombinesWithNodeAndView() {
        var query = NavigationModel.catalogQuery(for: .global)!
        query.searchText = "twin"
        #expect(query.apply(catalog: catalog).map(\.name) == ["twin"])
    }

    /// 导航标题反映当前视图（i18n：中英双语）。
    @Test func nodeTitles() {
        let zh = L10n(lang: .zhHans)
        let en = L10n(lang: .english)
        #expect(NavigationModel.listTitle(for: .all, l10n: zh) == "Skills")
        #expect(NavigationModel.listTitle(for: .global, l10n: zh) == "Skills · 全局")
        #expect(NavigationModel.listTitle(for: .agent("claude-code"), l10n: zh) == "Skills · claude-code")
        #expect(NavigationModel.listTitle(for: .project("atlas"), l10n: zh) == "Skills · atlas")
        #expect(NavigationModel.listTitle(for: .tag("hot"), l10n: zh) == "Skills · #hot")
        #expect(NavigationModel.listTitle(for: .global, l10n: en) == "Skills · Global")
        #expect(NavigationModel.listTitle(for: .zone(.disabled), l10n: en) == "Disabled")
    }
}

// MARK: - 节点失效归一（回落 .all）

@Suite struct SidebarNodeNormalizeTests {
    private func section(_ kind: NavigationSectionKind, _ title: String) -> NavigationSection {
        NavigationSection(kind: kind, title: title, count: 1, skills: [])
    }

    @Test func allAlwaysValid() {
        let node = NavigationModel.normalize(
            node: .all,
            sections: [], tagTitles: [], installedAgentIDs: []
        )
        #expect(node == .all)
    }

    @Test func agentGoneFallsBackToAll() {
        let node = NavigationModel.normalize(
            node: .agent("removed-agent"),
            sections: [section(.global, "全局")], tagTitles: [], installedAgentIDs: ["claude-code"]
        )
        #expect(node == .all)
    }

    @Test func validAgentKept() {
        let node = NavigationModel.normalize(
            node: .agent("claude-code"),
            sections: [], tagTitles: [], installedAgentIDs: ["claude-code", "pi"]
        )
        #expect(node == .agent("claude-code"))
    }

    @Test func projectSectionMissingFallsBackToAll() {
        let node = NavigationModel.normalize(
            node: .project("gone-project"),
            sections: [section(.global, "全局"), section(.project, "atlas")],
            tagTitles: [], installedAgentIDs: []
        )
        #expect(node == .all)
    }

    @Test func tagMissingFallsBackToAll() {
        let node = NavigationModel.normalize(
            node: .tag("gone-tag"),
            sections: [], tagTitles: ["kept"], installedAgentIDs: []
        )
        #expect(node == .all)
    }

    @Test func globalNodeKeptWhileSectionExists() {
        let node = NavigationModel.normalize(
            node: .global,
            sections: [section(.global, "全局")], tagTitles: [], installedAgentIDs: []
        )
        #expect(node == .global)
    }

    /// 全局节为空（catalog 全是 agentOnly）时「全局」节点失效回落。
    @Test func globalNodeInvalidWithoutGlobalSection() {
        let node = NavigationModel.normalize(
            node: .global,
            sections: [], tagTitles: [], installedAgentIDs: []
        )
        #expect(node == .all)
    }

    /// 生命周期区目录常驻，节点恒有效。
    @Test func zoneNodesAlwaysValid() {
        for zone in LifecycleZone.allCases {
            let node = NavigationModel.normalize(
                node: .zone(zone),
                sections: [], tagTitles: [], installedAgentIDs: []
            )
            #expect(node == .zone(zone))
        }
    }
}
