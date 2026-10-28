import Foundation
import Testing
import AppCore
import DomainKit
@testable import AgentKeeperUI

/// 总览模型（MangoDisk 式扫描结果仪表盘的数据底座）：
/// 未选中 skill 时主界面展示扫描产出全貌——统计、作用域分布、agent 卡片。
@MainActor
@Suite struct OverviewModelTests {
    @Test func buildAggregatesStats() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let skills = UIWiring.demoSkills(home: home) // 2 agent × 2 skill + 1 全局

        var state = AppState.initial
        state.agents = [
            Agent(id: "agent-0", name: "agent-0", installState: .installed(configDirectory: nil)),
            Agent(id: "agent-1", name: "agent-1", installState: .installed(configDirectory: nil)),
        ]

        let model = OverviewModel.build(state: state, skills: skills, tagCount: 3)

        #expect(model.totalSkills == 5)
        #expect(model.installedAgents == 2)
        #expect(model.scopeCounts[.global] == 1)
        #expect(model.scopeCounts[.agentOnly] == 4)
        #expect(model.tagCount == 3)
        // agent 卡片：各自可用 skill 数（专属 2 + 全局共享 1 = 3；agent 可加载全局 skill）
        #expect(model.agentEntries.first { $0.id == "agent-0" }?.skillCount == 3)
        #expect(model.agentEntries.first { $0.id == "agent-1" }?.skillCount == 3)
    }

    @Test func emptyCatalogYieldsZeros() {
        var state = AppState.initial
        state.agents = []
        let model = OverviewModel.build(state: state, skills: [], tagCount: 0)
        #expect(model.totalSkills == 0)
        #expect(model.installedAgents == 0)
        #expect(model.agentEntries.isEmpty)
    }
}
