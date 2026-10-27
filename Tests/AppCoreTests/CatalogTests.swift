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
    @Test func syncPersistsToIndexAndReloadsWillCache() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-catalog-\(UUID().uuidString)", isDirectory: true)
        let index = SkillIndex(databaseDirectory: dir)
        let store = CatalogStore(index: index)
        let alpha = Skill(id: "alpha|claude-code", name: "alpha", directory: URL(fileURLWithPath: "/tmp/a"), scope: .agentOnly(agentID: "claude-code"), sha256: "s")
        store.sync(with: [alpha])
        #expect(store.current.count == 1)

        // 从缓存重建的 store 恢复条目（应用重启场景）
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
}
