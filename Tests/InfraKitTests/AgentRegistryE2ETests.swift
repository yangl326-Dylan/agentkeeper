import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 端到端：用户自定义 agent 与内置 agent 走同一条扫描管线（含项目级目录）。
@Suite struct AgentRegistryE2ETests {
    private func writeConfig(_ home: URL, _ json: String) {
        let base = home.appendingPathComponent(".agentkeeper", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        try? json.write(to: base.appendingPathComponent("agents.json"), atomically: true, encoding: .utf8)
    }

    private let windsurfConfig = """
    {"agents":[{
      "id":"windsurf",
      "displayName":"Windsurf",
      "detectionSubpaths":[".windsurf"],
      "skillRootCandidates":[".windsurf/skills"],
      "projectSkillSubpaths":[".windsurf/skills"]
    }]}
    """

    @Test func userAgentScannedEndToEnd() async {
        let home = makeFakeHome(files: [".windsurf/skills/foo/SKILL.md"])
        defer { cleanup(home) }
        writeConfig(home, windsurfConfig)

        let registry = AgentRegistry(homeDirectory: home)
        let report = await ScanScheduler(registry: registry).scanAll()

        guard let agent = report.agents.first(where: { $0.id == "windsurf" }) else {
            Issue.record("custom agent not scanned: \(report.agents.map(\.id))")
            return
        }
        guard case .installed = agent.installState else {
            Issue.record("expected installed, got \(agent.installState)")
            return
        }
        #expect(agent.skillRoots.contains { $0.path.path.hasSuffix("/.windsurf/skills") })
        #expect(report.diagnostics.isEmpty)
    }

    /// 自定义 agent 的项目级目录也要被 ProjectRootScanner 覆盖（spec 派生）。
    @Test func userAgentProjectSkillRootsScanned() async {
        let home = makeFakeHome(files: ["code/atlas/.windsurf/skills/foo/SKILL.md"])
        defer { cleanup(home) }
        writeConfig(home, windsurfConfig)

        let projectRoot = ProjectRoot(path: home.appendingPathComponent("code/atlas", isDirectory: true))
        let registry = AgentRegistry(homeDirectory: home)
        let report = await ScanScheduler(registry: registry).scanAll(knownProjectRoots: [projectRoot])

        guard let agent = report.agents.first(where: { $0.id == "windsurf" }) else {
            Issue.record("custom agent not scanned")
            return
        }
        let projectRoots = agent.skillRoots.filter {
            if case .project = $0.level { return true }
            return false
        }
        #expect(projectRoots.contains { $0.path.path.hasSuffix("/.windsurf/skills") })
    }

    /// 配置损坏：扫描继续，诊断里说明问题（绝不静默当作没有配置）。
    @Test func invalidConfigSurfacesDiagnosticButScanContinues() async {
        let home = makeFakeHome(files: [".claude/skills/foo/SKILL.md"])
        defer { cleanup(home) }
        writeConfig(home, "{ broken")

        let registry = AgentRegistry(homeDirectory: home)
        let report = await ScanScheduler(registry: registry).scanAll()

        #expect(report.agents.contains { $0.id == "claude-code" })
        #expect(report.diagnostics.contains {
            $0.path.hasSuffix("agents.json") && $0.kind == .unrecognizedStructure
        })
    }
}
