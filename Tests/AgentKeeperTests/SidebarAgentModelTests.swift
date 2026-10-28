import Foundation
import Testing
import DomainKit
import AppCore
@testable import AgentKeeperUI

/// 侧栏 Agents 分组：只显示本机实际安装过的 agent（目录存在），
/// 未安装的 harness 不进侧栏；行内展示可用状态与 skill 数。
@MainActor
@Suite struct SidebarAgentModelTests {
    private func agent(_ id: String, _ state: AgentInstallState) -> Agent {
        Agent(id: id, name: id, installState: state)
    }

    @Test func hidesNotInstalledAgents() {
        let agents = [
            agent("claude-code", .installed(configDirectory: nil)),
            agent("codex", .notInstalled),
            agent("gemini", .notInstalled),
        ]
        let rows = SidebarAgentModel.build(agents: agents, skills: [])
        #expect(rows.map(\.id) == ["claude-code"])
    }

    @Test func installedRowShowsAvailableStatusWithSkillCount() {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let skills = UIWiring.demoSkills(home: home) // agent-0: 专属2 + 全局1
        let rows = SidebarAgentModel.build(
            agents: [agent("agent-0", .installed(configDirectory: nil))],
            skills: skills
        )
        #expect(rows.count == 1)
        #expect(rows[0].status == .available)
        #expect(rows[0].statusText == "可用 · 3 skills")
    }

    @Test func unrecognizedStructureKeptWithWarningStatus() {
        let rows = SidebarAgentModel.build(
            agents: [
                agent("weird-agent", .unrecognizedStructure(path: "/x/y")),
                agent("gone", .notInstalled),
            ],
            skills: []
        )
        #expect(rows.map(\.id) == ["weird-agent"])
        #expect(rows[0].status == .unrecognized)
        #expect(rows[0].statusText == "结构未知")
    }

    @Test func installedWithoutSkillsShowsZero() {
        let rows = SidebarAgentModel.build(
            agents: [agent("opencode", .installed(configDirectory: nil))],
            skills: []
        )
        #expect(rows[0].statusText == "可用 · 0 skills")
    }
}
