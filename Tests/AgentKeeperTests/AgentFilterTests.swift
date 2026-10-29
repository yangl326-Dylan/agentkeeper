import Foundation
import Testing
import DomainKit
import AppCore
@testable import AgentKeeperUI

/// 侧栏点击 agent → 列表按 agent 筛选（owners 命中，含全局共享）。
@MainActor
@Suite struct AgentFilterTests {
    @Test func filterBySelectedAgent() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home)) // agent-0: 专属2+全局1

        env.selectedAgent = "agent-0"
        let filtered = SkillListCore.filter("", env)
        #expect(filtered.count == 3)
        #expect(filtered.allSatisfy { $0.owners.contains("agent-0") })

        env.selectedAgent = nil
        #expect(SkillListCore.filter("", env).count == 5)
    }

    @Test func agentAndTagFiltersCoexist() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))
        let target = env.catalogStore.current.first { $0.name == "review" }!
        env.tagService.addTag("写作", toSkillID: target.id)

        env.selectedAgent = "agent-0"
        env.selectedTag = "写作"
        let filtered = SkillListCore.filter("", env)
        // 标签只打在 agent-0 的 review 上；agent 筛选不排斥它
        #expect(filtered.map(\.name) == ["review"])
    }

    @Test func agentSelectionToggles() {
        #expect(AgentSelection.toggle(current: nil, clicked: "opencode") == "opencode")
        #expect(AgentSelection.toggle(current: "opencode", clicked: "opencode") == nil)
        #expect(AgentSelection.toggle(current: "opencode", clicked: "claude-code") == "claude-code")
    }
}
