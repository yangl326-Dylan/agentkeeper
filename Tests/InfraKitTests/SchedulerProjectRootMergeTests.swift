import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SchedulerProjectRootTests {
    private func skillRoot(_ home: URL, _ subpath: String, owners: [AgentID]) -> SkillRoot {
        SkillRoot(path: home.appendingPathComponent(subpath, isDirectory: true), owners: owners, level: .user)
    }

    @Test func projectRootsEnrichOwnerAgents() async {
        let project = makeFakeHome(files: ["code/atlas/.claude/skills/proj/SKILL.md"])
        defer { cleanup(project) }
        let projectRoot = ProjectRoot(path: project.appendingPathComponent("code/atlas", isDirectory: true))
        let scheduler = ScanScheduler(registry: AgentRegistry(adapters: [
            FakeAdapter(id: "claude-code", install: .installed(configDirectory: nil), roots: [
                skillRoot(project, ".claude/skills-home", owners: ["claude-code"]),
            ]),
        ]))
        let report = await scheduler.scanAll(knownProjectRoots: [projectRoot])
        let claude = report.agents.first { $0.id == "claude-code" }
        #expect(claude != nil)
        let projectRoots = claude!.skillRoots.filter {
            if case .project = $0.level { return true }
            return false
        }
        #expect(projectRoots.count == 1)
        #expect(projectRoots[0].path == project.appendingPathComponent("code/atlas/.claude/skills", isDirectory: true))
        // 共享根索引同样把项目根纳入
        let projectSharedRoot = report.sharedRoots.first { $0.owners == ["claude-code"] && $0.level == .project(projectRoot) }
        #expect(projectSharedRoot != nil)
    }

    @Test func projectRootWithoutCandidatesContributesNothing() async {
        let project = makeFakeHome(files: ["code/empty/readme.md"])
        defer { cleanup(project) }
        let projectRoot = ProjectRoot(path: project.appendingPathComponent("code/empty", isDirectory: true))
        let scheduler = ScanScheduler(registry: AgentRegistry(adapters: [
            FakeAdapter(id: "claude-code", install: .installed(configDirectory: nil), roots: []),
        ]))
        let report = await scheduler.scanAll(knownProjectRoots: [projectRoot])
        #expect(report.agents.count == 1)
        #expect(report.sharedRoots.isEmpty)
    }
}
