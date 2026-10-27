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

    @Test func threeSectionKindsInCanonicalOrder() {
        let sections = NavigationModel.buildSections(skills: [
            skill("proj-skill", scope: .project(agentID: "claude-code", root: ProjectRoot(path: "/users/x/code/atlas"))),
            skill("only-pi", scope: .agentOnly(agentID: "pi")),
            skill("shared", scope: .global(owners: ["claude-code", "pi"])),
        ])
        #expect(sections.map({ $0.kind }) == [.global, .agent, .project])
        #expect(sections[0].title == "全局")
        #expect(sections[1].title == "pi")
        #expect(sections[2].title == "atlas")
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

    @Test func agentOnlyGroupsByOwnerAgent() {
        let sections = NavigationModel.buildSections(skills: [
            skill("a", scope: .agentOnly(agentID: "opencode")),
            skill("b", scope: .agentOnly(agentID: "opencode")),
            skill("c", scope: .agentOnly(agentID: "claude-code")),
        ])
        let agentSections = sections.filter { $0.kind == .agent }
        #expect(agentSections.count == 2)
        #expect(agentSections.first { $0.title == "opencode" }?.count == 2)
        // 无全局 skill 时无"全局"节（空节不占位）
        #expect(!sections.contains { $0.kind == .global })
    }
}
