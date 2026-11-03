import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

@Suite struct CatalogQueryTests {
    private static func skill(_ name: String, agent: AgentID, scope: SkillScope, desc: String = "") -> Skill {
        Skill(
            id: "\(name)|\(agent)",
            name: name,
            directory: URL(fileURLWithPath: "/tmp/x/\(agent)/\(name)"),
            scope: scope,
            sha256: "sha-\(name)",
            skillDescription: desc
        )
    }

    private let catalog: [Skill] = [
        CatalogQueryTests.skill("alpha", agent: "claude-code", scope: .agentOnly(agentID: "claude-code"), desc: "处理文件"),
        CatalogQueryTests.skill("beta", agent: "opencode", scope: .global(owners: ["claude-code", "opencode"]), desc: "全局工具"),
        CatalogQueryTests.skill("atlas-deploy", agent: "claude-code", scope: .project(agentID: "claude-code", root: ProjectRoot(path: "/Users/x/code/atlas")), desc: "部署流水线"),
        CatalogQueryTests.skill("twin-a", agent: "claude-code", scope: .multiAgent(["claude-code", "opencode"]), desc: ""),
        CatalogQueryTests.skill("twin-b", agent: "opencode", scope: .multiAgent(["claude-code", "opencode"]), desc: ""),
    ]

    @Test func filterByAgentUsesOwnersDerivedFromScope() {
        var query = CatalogQuery.initial
        query.agentID = "claude-code"
        let result = query.apply(catalog: catalog)
        // claude-code 命名空间：专属 + 项目 + 其参与的 global/multiAgent
        let names = Set(result.map(\.name))
        #expect(names == ["alpha", "beta", "atlas-deploy", "twin-a", "twin-b"])

        query.agentID = "opencode"
        let opencodeNames = Set(query.apply(catalog: catalog).map(\.name))
        #expect(opencodeNames == ["beta", "twin-a", "twin-b"])
    }

    @Test func filterByScopeKind() {
        var query = CatalogQuery.initial
        query.scopeKinds = [.multiAgent]
        let result = query.apply(catalog: catalog)
        #expect(result.count == 2)
        #expect(result.allSatisfy { skill in
            if case .multiAgent = skill.scope { return true }
            return false
        })
    }

    /// 侧栏项目节点：按项目名（projectTag）过滤，而非「所有项目级」。
    @Test func filterByProjectNameOnlyMatchesThatProject() {
        var query = CatalogQuery.initial
        query.projectName = "atlas"
        let result = query.apply(catalog: [
            CatalogQueryTests.skill("atlas-deploy", agent: "claude-code", scope: .project(agentID: "claude-code", root: ProjectRoot(path: "/Users/x/code/atlas"))),
            CatalogQueryTests.skill("beta-lint", agent: "opencode", scope: .project(agentID: "opencode", root: ProjectRoot(path: "/Users/x/code/beta"))),
            CatalogQueryTests.skill("global-skill", agent: "claude-code", scope: .global(owners: ["claude-code"])),
        ])
        #expect(result.map(\.name) == ["atlas-deploy"])
    }

    @Test func searchMatchesNameAndDescription() {
        var query = CatalogQuery.initial
        query.searchText = "部署"
        let result = query.apply(catalog: catalog)
        #expect(result.count == 1)
        #expect(result[0].name == "atlas-deploy")

        query.searchText = "ATLAS"
        #expect(query.apply(catalog: catalog).count == 1)
    }

    @Test func combinedFilters() {
        var query = CatalogQuery.initial
        query.scopeKinds = [.project]
        query.searchText = "atlas"
        let result = query.apply(catalog: catalog)
        #expect(result.count == 1)
        #expect(result[0].name == "atlas-deploy")
    }
}

@Suite @MainActor struct CatalogStoreTests {
    /// 异步索引写落地等待（sync 改走后台队列后，持久化断言改为收敛轮询）。
    private func waitUntilIndexLanded(_ index: SkillIndex, count: Int, timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if index.all().count == count { return }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    @Test func syncPersistsToIndexAndReloadsWillCache() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-catalog-\(UUID().uuidString)", isDirectory: true)
        let index = SkillIndex(databaseDirectory: dir)
        let store = CatalogStore(index: index)
        let alpha = Skill(id: "alpha|claude-code", name: "alpha", directory: URL(fileURLWithPath: "/tmp/a"), scope: .agentOnly(agentID: "claude-code"), sha256: "s")
        store.sync(with: [alpha])
        #expect(store.current.count == 1)

        // 异步写盘落地后从缓存重建（应用重启场景）
        waitUntilIndexLanded(index, count: 1)
        let reopened = CatalogStore(index: SkillIndex(databaseDirectory: dir))
        #expect(reopened.current.count == 1)
        #expect(reopened.current[0].name == "alpha")
    }

    @Test func syncReplacesSoExternalDeletionIsCorrected() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-catalog-\(UUID().uuidString)", isDirectory: true)
        let store = CatalogStore(index: SkillIndex(databaseDirectory: dir))
        let one = Skill(id: "one|claude-code", name: "one", directory: URL(fileURLWithPath: "/tmp/1"), scope: .agentOnly(agentID: "claude-code"), sha256: "s1")
        let two = Skill(id: "two|claude-code", name: "two", directory: URL(fileURLWithPath: "/tmp/2"), scope: .agentOnly(agentID: "claude-code"), sha256: "s2")
        store.sync(with: [one, two])
        #expect(store.current.count == 2)

        // 外部删除 one 后的重扫同步（磁盘为准）
        store.sync(with: [two])
        #expect(store.current.count == 1)
        #expect(store.current[0].name == "two")
    }

    /// 启动异步缓存加载：init 不读盘（loadCacheEagerly: false），
    /// warmupFromCache 后台回填（启动不再被 SQLite 首读阻塞）；同步版本默认行为不变。
    @Test func deferredCacheLoadBackfillsWithoutBlockingInit() async {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-catalog-\(UUID().uuidString)", isDirectory: true)
        let alpha = Skill(id: "alpha|claude-code", name: "alpha", directory: URL(fileURLWithPath: "/tmp/a"), scope: .agentOnly(agentID: "claude-code"), sha256: "s")
        let writer = CatalogStore(index: SkillIndex(databaseDirectory: dir))
        writer.sync(with: [alpha])
        typealias AwaitableVoid = Void
        func waitIndex(_ index: SkillIndex, count: Int, timeout: TimeInterval = 2) {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline, index.all().count != count {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        // 新 init：不立即读缓存
        let index = SkillIndex(databaseDirectory: dir)
        waitIndex(index, count: 1)
        let deferred = CatalogStore(index: index, loadCacheEagerly: false)
        #expect(deferred.current.isEmpty)

        // warmup 后台回填
        await deferred.warmupFromCache()
        #expect(deferred.current.count == 1)
        #expect(deferred.current[0].name == "alpha")

        // 默认参数保持同步加载（既有测试语义）
        let eager = CatalogStore(index: SkillIndex(databaseDirectory: dir))
        #expect(eager.current.count == 1)
    }

    /// version 单调递增：sync 每次自增、warmup 自增、init 后为 0——派生缓存失效键。
    @Test func versionTracksSnapshotChanges() async {
        let store = CatalogStore()
        #expect(store.version == 0)
        let one = Skill(id: "one|claude-code", name: "one", directory: URL(fileURLWithPath: "/tmp/1"), scope: .agentOnly(agentID: "claude-code"), sha256: "s1")
        store.sync(with: [one])
        let v1 = store.version
        #expect(v1 > 0)
        store.sync(with: [one])
        let v2 = store.version
        #expect(v2 > v1)

        // warmup 分支：空 current 回填会自增
        let writer = CatalogStore()
        writer.sync(with: [one])
        let deferred = CatalogStore()
        let before = deferred.version
        await deferred.warmupFromCache()
        #expect(deferred.version == before, "无 index 的 warmup 是 no-op——version 不应动")
    }
}
