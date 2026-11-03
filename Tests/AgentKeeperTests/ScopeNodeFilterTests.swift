import Foundation
import Testing
import DomainKit
import AppCore
@testable import AgentKeeperUI

/// 作用域节点 → 列表：全局含 global + multiAgent；项目节点按项目名过滤
/// （旧实现只按 [.project] 大类——所有项目混在一起，属缺陷修复）。
@MainActor
@Suite struct ScopeNodeFilterTests {
    private func skill(_ name: String, scope: SkillScope, home: URL) -> Skill {
        Skill(
            id: "\(name)|t",
            name: name,
            directory: home.appendingPathComponent(name),
            scope: scope,
            sha256: "s-\(name)",
            skillDescription: "d"
        )
    }

    @Test func globalNodeShowsGlobalAndMultiAgentOnly() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home)) // 4 agentOnly + 1 global

        env.select(node: .global)
        #expect(SkillListCore.filter("", env).count == 1)

        env.select(node: .all)
        #expect(SkillListCore.filter("", env).count == 5)
    }

    @Test func projectNodeFiltersByProjectName() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        let atlas = ProjectRoot(path: home.appendingPathComponent("atlas").path)
        let beta = ProjectRoot(path: home.appendingPathComponent("beta").path)
        env.catalogStore.sync(with: [
            skill("atlas-deploy", scope: .project(agentID: "claude-code", root: atlas), home: home),
            skill("atlas-lint", scope: .project(agentID: "opencode", root: atlas), home: home),
            skill("beta-lint", scope: .project(agentID: "claude-code", root: beta), home: home),
            skill("global-one", scope: .global(owners: ["claude-code"]), home: home),
        ])

        env.select(node: .project("atlas"))
        #expect(Set(SkillListCore.filter("", env).map(\.name)) == ["atlas-deploy", "atlas-lint"])

        env.select(node: .project("beta"))
        #expect(SkillListCore.filter("", env).map(\.name) == ["beta-lint"])
    }

    /// 节点失效归一：agent 卸载后回落「所有 Skills」（UI 层 onChange 调 normalize）。
    @Test func normalizeDropsMissingAgentNode() {
        let dropped = NavigationModel.normalize(
            node: .agent("gone-agent"),
            sections: [], tagTitles: [], installedAgentIDs: ["agent-0"]
        )
        #expect(dropped == .all)

        let kept = NavigationModel.normalize(
            node: .agent("agent-0"),
            sections: [], tagTitles: [], installedAgentIDs: ["agent-0"]
        )
        #expect(kept == .agent("agent-0"))
    }
}
