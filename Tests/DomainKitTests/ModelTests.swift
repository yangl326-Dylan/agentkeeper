import Foundation
import Testing
@testable import DomainKit

// MARK: - ProjectRoot 项目标签派生

@Suite struct ProjectRootTests {
    @Test func projectTagNameDerivedFromLastPathComponent() {
        let root = ProjectRoot(path: "/Users/dylan/code/atlas-ui")
        #expect(root.tagName == "atlas-ui")
    }

    @Test func projectRootWithTrailingSlashStillDerivesName() {
        let root = ProjectRoot(path: "/Users/dylan/code/my_project/")
        #expect(root.tagName == "my_project")
    }
}

// MARK: - SkillScope 语义

@Suite struct SkillScopeTests {
    @Test func scopesCodableRoundTrip() throws {
        let scopes: [SkillScope] = [
            .global(owners: ["claude-code", "opencode"]),
            .agentOnly(agentID: "claude-code"),
            .project(agentID: "openclaw", root: ProjectRoot(path: "/tmp/demo")),
            .multiAgent(["claude-code", "opencode"]),
        ]
        let data = try JSONEncoder().encode(scopes)
        let decoded = try JSONDecoder().decode([SkillScope].self, from: data)
        #expect(decoded == scopes)
    }

    @Test func projectScopeCarriesAgentAndRoot() {
        let root = ProjectRoot(path: "/Users/dylan/code/atlas-ui")
        let scope = SkillScope.project(agentID: "claude-code", root: root)
        #expect(scope.agentIDForOwner == "claude-code")
        #expect(scope.projectRoot == root)
    }

    @Test func nonProjectScopesHaveNoProjectRoot() {
        #expect(SkillScope.global(owners: ["a"]).projectRoot == nil)
        #expect(SkillScope.agentOnly(agentID: "pi").projectRoot == nil)
        #expect(SkillScope.multiAgent(["a"]).projectRoot == nil)
    }
}

// MARK: - AgentInstallState

@Suite struct AgentInstallStateTests {
    @Test func installStatesRoundTrip() throws {
        let states: [AgentInstallState] = [
            .installed(configDirectory: URL(fileURLWithPath: "/Users/x/.claude")),
            .notInstalled,
            .unrecognizedStructure(path: "/Users/x/.mystery"),
        ]
        let data = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([AgentInstallState].self, from: data)
        #expect(decoded == states)
    }
}

// MARK: - ScanReport 聚合

@Suite struct ScanReportTests {
    @Test func scanReportMergesAgentDiagnostics() {
        var report = ScanReport.empty
        report.add(
            agent: Agent(
                id: "claude-code",
                name: "Claude Code",
                installState: .installed(configDirectory: URL(fileURLWithPath: "/Users/x/.claude")),
                skillRoots: [
                    SkillRoot(
                        path: URL(fileURLWithPath: "/Users/x/.claude/skills"),
                        owners: ["claude-code"],
                        level: .user
                    )
                ]
            ),
            diagnostics: [
                ScanDiagnostic(
                    path: "/Users/x/.claude/plugins/weird",
                    kind: .unrecognizedStructure,
                    agentID: "claude-code",
                    message: "结构未知"
                )
            ]
        )
        #expect(report.agents.count == 1)
        #expect(report.diagnostics.count == 1)
        #expect(report.agents[0].skillRoots[0].owners == ["claude-code"])
    }
}
