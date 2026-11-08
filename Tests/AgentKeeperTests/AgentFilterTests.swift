import Foundation
import Testing
import DomainKit
import AppCore
@testable import AgentKeeperUI

/// 侧栏导航节点 → 列表筛选（节点集合 ∩ 搜索词；单选、无 toggle-off 语义）。
@MainActor
@Suite struct AgentFilterTests {
    @Test func agentNodeFiltersListByOwners() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home)) // agent-0: 专属2+全局1

        env.select(node: .agent("agent-0"))
        let filtered = SkillListCore.filter("", env)
        #expect(filtered.count == 3)
        #expect(filtered.allSatisfy { $0.owners.contains("agent-0") })

        env.select(node: .all)
        #expect(SkillListCore.filter("", env).count == 5)
    }

    /// 导航语义：重复选中同一节点不取消（回到全量走「所有 Skills」节点）。
    @Test func selectingSameNodeTwiceKeepsSelection() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))

        env.select(node: .agent("agent-0"))
        env.select(node: .agent("agent-0"))
        #expect(env.selectedNode == .agent("agent-0"))
        #expect(SkillListCore.filter("", env).count == 3)
    }

    /// 视图切换清掉列表选中（新视图内可能不存在该 skill）。
    @Test func switchingNodeClearsSkillSelection() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))

        env.select(node: .agent("agent-0"))
        env.selectedSkillID = "any"
        env.select(node: .all)
        #expect(env.selectedSkillID == nil)
        // 同节点重复 select 不清（视图未变，无谓清空）
        env.selectedSkillID = "any"
        env.select(node: .all)
        #expect(env.selectedSkillID == "any")
    }

    /// 标签是独立节点（导航语义）：切到标签节点只看带标签 skill，切走即恢复，无 AND 组合。
    @Test func tagNodeShowsOnlyTaggedSkills() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))
        let target = env.catalogStore.current.first { $0.name == "review" }!
        env.tagService.addTag("写作", toSkillID: target.id)

        env.select(node: .tag("写作"))
        #expect(SkillListCore.filter("", env).map(\.name) == ["review"])

        env.select(node: .agent("agent-0"))
        #expect(SkillListCore.filter("", env).count == 3) // 不与标签 AND
    }

    /// 状态栏 agent 行：设置 agent 节点、清空选中、每次调用都递增搜索重置 token。
    @Test func openAgentFilterSetsAgentNodeAndClearsSearch() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)

        env.selectedSkillID = "any"
        let before = env.searchResetToken

        env.openAgentFilter("agent-0")
        #expect(env.selectedNode == .agent("agent-0"))
        #expect(env.selectedSkillID == nil)
        #expect(env.searchResetToken == before + 1)

        // 重复点同一个 agent 也要再次清空搜索
        env.selectedSkillID = "any"
        env.openAgentFilter("agent-0")
        #expect(env.selectedSkillID == nil)
        #expect(env.searchResetToken == before + 2)
    }
}
