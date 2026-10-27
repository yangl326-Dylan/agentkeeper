import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 7.1 自动化 E2E：本机验收清单的可注入 fake-home 版本。
/// 覆盖：扫描→浏览（catalog/筛选）→禁用→恢复→修改触发快照→diff→恢复旧版本→（菜单摘要）。
/// GUI 交互走查由验收清单人工完成（acceptance.md）。
@Suite struct E2EWorkflowTests {
    @Test func fullLifecycleWorkflowOnFakeHome() async throws {
        // ── 环境搭建：fake 家目录 + 双 agent + 共享根 + 项目根
        let home = makeFakeHome(
            files: [
                ".claude/skills/claude-only/SKILL.md",
                ".config/opencode/skill/opencode-only/SKILL.md",
                "shared-kit/shared-skill/SKILL.md",
                "code/atlas/.claude/skills/atlas-deploy/SKILL.md",
            ],
            fileContents: [
                ".claude/skills/claude-only/SKILL.md": "---\nname: claude-only\ndescription: 专属\n---\nC",
                ".config/opencode/skill/opencode-only/SKILL.md": "---\nname: opencode-only\ndescription: 专属\n---\nO",
                "shared-kit/shared-skill/SKILL.md": "---\nname: shared-skill\ndescription: 共享\n---\nS",
                "code/atlas/.claude/skills/atlas-deploy/SKILL.md": "---\nname: atlas-deploy\ndescription: 项目部署\n---\nV1",
            ]
        )
        defer { cleanup(home) }
        let base = home.appendingPathComponent(".agentkeeper", isDirectory: true)
        let projectRoot = ProjectRoot(path: home.appendingPathComponent("code/atlas", isDirectory: true))

        // ── 扫描
        let scheduler = ScanScheduler(registry: FakeAdapterRegistry(home: home).registry)
        let report = await scheduler.scanAll(knownProjectRoots: [projectRoot])
        #expect(report.agents.count == 2)

        // ── 编目 + 作用域
        let catalog = CatalogBuilder().build(agents: report.agents)
        let byName = { (name: String) throws -> Skill in
            guard let skill = catalog.first(where: { $0.name == name }) else {
                throw SkillLifecycleError.sourceMissing(path: name)
            }
            return skill
        }
        let shared = try byName("shared-skill")
        guard case .global = shared.scope else {
            Issue.record("共享根应为 global：\(shared.scope)")
            return
        }
        let atlasDeploy = try byName("atlas-deploy")
        guard case .project(_, let root) = atlasDeploy.scope, root.tagName == "atlas" else {
            Issue.record("项目 skill 应有 atlas 标签：\(atlasDeploy.scope)")
            return
        }

        // ── 筛选浏览（CatalogQuery）
        var query = CatalogQuery.initial
        query.scopeKinds = [ScopeKind.project]
        #expect(query.apply(catalog: catalog).map { $0.name } == ["atlas-deploy"])

        // ── 禁用 → 禁用区
        let lifecycle = SkillLifecycle(baseDirectory: base)
        let claudeOnly = try byName("claude-only")
        let record = try lifecycle.disable(agentID: claudeOnly.owners.first ?? "claude-code", skillDirectory: claudeOnly.directory)
        #expect(!FileManager.default.fileExists(atPath: claudeOnly.directory.path))
        #expect(FileManager.default.fileExists(
            atPath: base.appendingPathComponent("disabled/claude-code/claude-only/SKILL.md").path
        ))
        #expect(record.originalPath == claudeOnly.directory.path)

        // ── 恢复 → 回原路径 manifest 清理
        try lifecycle.enable(agentID: "claude-code", name: "claude-only")
        #expect(FileManager.default.fileExists(atPath: claudeOnly.directory.appendingPathComponent("SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("disabled/claude-code/claude-only").path))

        // ── 内容修改 → 快照 → diff → 恢复旧版本（字节级一致）
        let snapshots = SnapshotStore(baseDirectory: base)
        let first = try snapshots.record(skillID: atlasDeploy.id, directory: atlasDeploy.directory)
        try "---\nname: atlas-deploy\ndescription: 项目部署\n---\nV2 改版".write(
            to: atlasDeploy.directory.appendingPathComponent("SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let second = try snapshots.record(skillID: atlasDeploy.id, directory: atlasDeploy.directory)
        #expect(first != nil && second != nil && first!.sha != second!.sha)
        let diff = try SnapshotDiffer.diff(
            before: snapshots.snapshotURL(skillID: atlasDeploy.id, sha: first!.sha),
            after: snapshots.snapshotURL(skillID: atlasDeploy.id, sha: second!.sha)
        )
        #expect(diff.modified.count == 1)
        try snapshots.restore(skillID: atlasDeploy.id, sha: first!.sha, currentDirectory: atlasDeploy.directory)
        let restored = try String(contentsOf: atlasDeploy.directory.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(restored.contains("V1") && !restored.contains("V2"))
    }
}

/// E2E 用的双 agent 注册表（claude-code + opencode，语义与真实 adapter 一致）。
final class FakeAdapterRegistry {
    let home: URL
    init(home: URL) { self.home = home }

    var registry: AgentRegistry {
        AgentRegistry(adapters: [
            FakeAdapter(id: "claude-code", install: .installed(configDirectory: nil), roots: [
                SkillRoot(path: home.appendingPathComponent(".claude/skills", isDirectory: true), owners: ["claude-code"], level: .user),
                SkillRoot(path: home.appendingPathComponent("shared-kit", isDirectory: true), owners: ["claude-code", "opencode"], level: .user),
            ]),
            FakeAdapter(id: "opencode", install: .installed(configDirectory: nil), roots: [
                SkillRoot(path: home.appendingPathComponent(".config/opencode/skill", isDirectory: true), owners: ["opencode"], level: .user),
                SkillRoot(path: home.appendingPathComponent("shared-kit", isDirectory: true), owners: ["claude-code", "opencode"], level: .user),
            ]),
        ])
    }
}
