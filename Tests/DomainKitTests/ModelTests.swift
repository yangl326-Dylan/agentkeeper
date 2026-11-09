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

@Suite struct SkillHealthModelTests {
    /// SkillIssue 编解码 roundtrip。
    @Test func skillIssueRoundTrip() throws {
        let issue = SkillIssue(kind: .missingDescription)
        let data = try JSONEncoder().encode(issue)
        let decoded = try JSONDecoder().decode(SkillIssue.self, from: data)
        #expect(decoded == issue)
    }

    /// 旧 JSON（无新字段）解码得到默认值——防御未来缓存/测试 fixture。
    @Test func skillDecodesLegacyJSONWithoutNewFields() throws {
        let skill = Skill(
            id: "s1", name: "demo", directory: URL(fileURLWithPath: "/tmp/demo"),
            scope: .global(owners: ["claude-code"]), status: .enabled, sha256: "abc",
            frontmatterName: nil, skillDescription: nil, fileCount: 2, lastModified: nil,
            totalBytes: 100, skillMdBytes: 50, issues: [SkillIssue(kind: .emptySkillMd)],
            shadowedBy: "s0", shadowedCount: 2
        )
        #expect(skill.totalBytes == 100) // memberwise init 生效
        #expect(skill.shadowedBy == "s0")
        #expect(skill.shadowedCount == 2)
        let data = try JSONEncoder().encode(skill)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["totalBytes", "skillMdBytes", "issues", "shadowedBy", "shadowedCount"] {
            object.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(Skill.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.totalBytes == 0)
        #expect(legacy.skillMdBytes == 0)
        #expect(legacy.issues.isEmpty)
        #expect(legacy.shadowedBy == nil)
        #expect(legacy.shadowedCount == 0)
        #expect(legacy.name == "demo")
    }

    /// ParsedSkill 旧 JSON（无新字段）同样可解码。
    @Test func parsedSkillDecodesLegacyJSONWithoutNewFields() throws {
        let parsed = ParsedSkill(
            directory: URL(fileURLWithPath: "/tmp/demo"), frontmatterName: "demo",
            frontmatterDescription: "d", files: [], sha256: "abc",
            totalBytes: 10, skillMdBytes: 5, issues: [SkillIssue(kind: .emptySkillMd)]
        )
        let data = try JSONEncoder().encode(parsed)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["totalBytes", "skillMdBytes", "issues"] { object.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(ParsedSkill.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.totalBytes == 0)
        #expect(legacy.skillMdBytes == 0)
        #expect(legacy.issues.isEmpty)
    }
}
