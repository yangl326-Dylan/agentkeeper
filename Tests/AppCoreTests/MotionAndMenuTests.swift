import Foundation
import Testing
import DomainKit
@testable import AppCore

@Suite struct MotionPolicyTests {
    @Test func normalSystemGivesSnappyMacosAnimations() {
        let policy = MotionPolicy(reduceMotion: false)
        #expect(policy.animation(for: .listTransition) != nil)
        #expect(policy.animation(for: .detailTransition) != nil)
        // 扫描呼吸态是装饰性动效：默认有
        #expect(policy.animation(for: .scanPulse) != nil)
    }

    @Test func reduceMotionDisablesAllDecorativeMotion() {
        let policy = MotionPolicy(reduceMotion: true)
        #expect(policy.animation(for: .listTransition) == nil)
        #expect(policy.animation(for: .detailTransition) == nil)
        #expect(policy.animation(for: .scanPulse) == nil)
    }
}

@Suite struct MenuBarSummaryTests {
    private func skill(_ name: String, owner: AgentID) -> Skill {
        Skill(
            id: "\(name)|\(owner)",
            name: name,
            directory: URL(fileURLWithPath: "/tmp/x/\(owner)/\(name)"),
            scope: .agentOnly(agentID: owner),
            sha256: "s"
        )
    }

    @Test func summaryListsInstalledAgentsWithTheirCounts() {
        var state = AppState.initial
        state.agents = [
            Agent(id: "claude-code", name: "Claude Code", installState: .installed(configDirectory: nil)),
            Agent(id: "codex", name: "Codex CLI", installState: .notInstalled),
        ]
        let skills = [
            skill("alpha", owner: "claude-code"),
            skill("beta", owner: "claude-code"),
        ]
        let summary = MenuBarSummary.build(state: state, skills: skills)
        #expect(summary.totalSkills == 2)
        #expect(summary.agentEntries.count == 2)
        let claude = summary.agentEntries.first { $0.id == "claude-code" }
        #expect(claude?.skillCount == 2)
        #expect(claude?.installed == true)
        let codex = summary.agentEntries.first { $0.id == "codex" }
        #expect(codex?.installed == false)
        #expect(codex?.skillCount == 0)
    }

    @Test func globalSkillsCountTowardEveryOwner() {
        var state = AppState.initial
        state.agents = [
            Agent(id: "claude-code", name: "Claude Code", installState: .installed(configDirectory: nil)),
            Agent(id: "pi", name: "pi", installState: .installed(configDirectory: nil)),
        ]
        let sharedSkill = Skill(
            id: "shared|s",
            name: "shared",
            directory: URL(fileURLWithPath: "/tmp/x/shared"),
            scope: .global(owners: ["claude-code", "pi"]),
            sha256: "s"
        )
        let summary = MenuBarSummary.build(state: state, skills: [sharedSkill])
        #expect(summary.agentEntries.first { $0.id == "claude-code" }?.skillCount == 1)
        #expect(summary.agentEntries.first { $0.id == "pi" }?.skillCount == 1)
        #expect(summary.totalSkills == 1)
    }
}
