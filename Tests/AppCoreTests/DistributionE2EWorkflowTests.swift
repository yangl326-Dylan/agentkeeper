import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 8.1：分发端到端工作流——git 安装 → 跨 agent 安装 → 铺设互链 → 外部改一处落点 → 分歧提示 → updateAllLandingPoints → 快照历史。
@Suite @MainActor struct DistributionE2EWorkflowTests {
    private struct Wiring {
        let home: URL
        let base: URL
        let store: AppStore
        let catalogStore: CatalogStore
        let service: DistributionService
        let tagService: TagService
        let snapshotStore: SnapshotStore
        let box: CatalogBox
    }

    private func makeWiring() -> Wiring {
        let home = makeFakeHome(files: ["dummy"])
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let store = AppStore()
        let catalogStore = CatalogStore(index: nil, initial: [])
        let history = OperationHistory(directory: base)
        let snapshotStore = SnapshotStore(baseDirectory: base)
        let snapshotService = SnapshotService(snapshots: snapshotStore, history: history, rescan: {})
        let box = CatalogBox()
        box.replace([])
        let service = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(git: GitInstaller(baseDirectory: base, timeout: TimeInterval(30))),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            catalogProvider: { box.skills },
            rescan: {}
        )
        let tagService = TagService(
            store: TagStore(directory: base),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true)
        )
        return Wiring(
            home: home, base: base, store: store, catalogStore: catalogStore,
            service: service, tagService: tagService, snapshotStore: snapshotStore,
            box: box
        )
    }

    /// Sendable catalog 快照盒（MainActor 外可读）。
    final class CatalogBox: @unchecked Sendable {
        private let lock = NSLock()
        private var skillsStorage: [Skill] = []
        var skills: [Skill] {
            lock.lock(); defer { lock.unlock() }
            return skillsStorage
        }
        func replace(_ skills: [Skill]) {
            lock.lock(); defer { lock.unlock() }
            self.skillsStorage = skills
        }
    }

    private func writeSkill(_ directory: URL, name: String, body: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: 正文\n---\n\(body)\n".write(
            to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
    }

    @Test func fullWorkflowFromGitToEqualizedLandingPoints() async throws {
        let w = makeWiring()
        defer { cleanup(w.home) }

        // 1. git 仓库（单 skill 仓库）→ 安装到 agent A
        let repo = w.home.appendingPathComponent("repo", isDirectory: true)
        try writeSkill(repo, name: "repo", body: "v1")
        let gitInit = Process()
        gitInit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitInit.arguments = ["init", "-q"]
        gitInit.currentDirectoryURL = repo
        try gitInit.run(); gitInit.waitUntilExit()
        #expect(gitInit.terminationStatus == 0)

        let rootA = w.home.appendingPathComponent("a/.claude/skills", isDirectory: true)
        let rootB = w.home.appendingPathComponent("b/.codex/skills", isDirectory: true)
        await w.service.install(
            source: .gitRepository(url: repo.path),
            targetSkillRoot: rootA,
            displaySkillID: "git|repo",
            displayName: "repo"
        )

        // 2. 跨 agent：从 A 的 skill 安装到 B
        let installedA = rootA.appendingPathComponent("repo", isDirectory: true)
        await w.service.install(
            source: .existingSkill(agentID: "claude-code", name: "repo", directoryPath: installedA.path),
            targetSkillRoot: rootB,
            displaySkillID: "cross|repo",
            displayName: "repo"
        )
        let installedB = rootB.appendingPathComponent("repo", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: installedB.path))

        // 3. 铺设互链：同名同指纹 → 两落点
        let shaValue = Fingerprint.sha256OfDirectory(installedA)!
        let shaB = Fingerprint.sha256OfDirectory(installedB)!
        let skillA = Skill(
            id: installedA.standardizedFileURL.path, name: "repo", directory: installedA,
            scope: .agentOnly(agentID: "claude-code"), sha256: shaValue
        )
        let skillB = Skill(
            id: installedB.standardizedFileURL.path, name: "repo", directory: installedB,
            scope: .agentOnly(agentID: "codex"), sha256: shaB
        )
        var catalog = [skillA, skillB]
        w.catalogStore.sync(with: catalog)
        w.box.replace(catalog)
        let points = CatalogQuery.landingPoints(named: "repo", catalog: catalog)
        #expect(points.count == 2)
        #expect(!CatalogQuery.isDiverged(name: "repo", catalog: catalog))

        // 3.5 标签随身走完整周期（tags 持久层独立于扫描）
        w.tagService.addTag("写作", toSkillID: skillA.id)
        #expect(w.tagService.tags(forSkillID: skillA.id) == ["写作"])

        // 4. 外部改 B 落点 → 分歧
        try "external-edit".write(
            to: installedB.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8
        )
        let skillBEdited = Skill(
            id: skillB.id, name: "repo", directory: installedB,
            scope: .agentOnly(agentID: "codex"), sha256: Fingerprint.sha256OfDirectory(installedB)!
        )
        catalog = [skillA, skillBEdited]
        w.catalogStore.sync(with: catalog)
        w.box.replace(catalog)
        #expect(CatalogQuery.isDiverged(name: "repo", catalog: catalog))

        // 5. 以 A 为基准更新所有落点 → 指纹一致 + 快照兜底
        let summary = await w.service.updateAllLandingPoints(from: skillA)
        #expect(summary.updated.count == 1)
        #expect(summary.failures.isEmpty)
        #expect(Fingerprint.sha256OfDirectory(installedB) == Fingerprint.sha256OfDirectory(installedA))
        #expect(w.snapshotStore.snapshots(skillID: skillBEdited.id).count == 1)

        // 6. 标签仍在：重扫/恢复周期后 assignment 保留（skillID 路径稳定）
        #expect(w.tagService.tags(forSkillID: skillA.id) == ["写作"])
    }

    /// 8.3：tags.json 损坏的 E2E——不影响安装与扫描语义。
    @Test func corruptTagStoreDoesNotBlockDistribution() async throws {
        let w = makeWiring()
        defer { cleanup(w.home) }
        // 先污染 tags.json（安装发生在后）
        let directory = w.base
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{broken".write(to: directory.appendingPathComponent("tags.json"), atomically: true, encoding: .utf8)

        let source = w.home.appendingPathComponent("source/review", isDirectory: true)
        try writeSkill(source, name: "review", body: "v1")
        let targetRoot = w.home.appendingPathComponent("agent/skills", isDirectory: true)
        await w.service.install(
            source: .localDirectory(path: source.path),
            targetSkillRoot: targetRoot,
            displaySkillID: "import|review",
            displayName: "review"
        )
        #expect(FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("review").path))
        // 标签层自愈后可用
        let recovered = TagService(
            store: TagStore(directory: w.base),
            disabledRoot: w.base.appendingPathComponent("disabled", isDirectory: true)
        )
        recovered.addTag("写作", toSkillID: targetRoot.appendingPathComponent("review").path)
        #expect(recovered.tags() == ["写作"])
    }
}
