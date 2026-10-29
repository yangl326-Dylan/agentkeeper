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
