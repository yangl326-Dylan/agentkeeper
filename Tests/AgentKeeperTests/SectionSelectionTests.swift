import Foundation
import Testing
import DomainKit
import AppCore
@testable import AgentKeeperUI

/// 侧栏 Skills 节点击 → 作用域筛选切换（点同节取消；全局节含同铺设）。
@MainActor
@Suite struct SectionSelectionTests {
    private func section(_ kind: NavigationSectionKind, _ title: String) -> NavigationSection {
        NavigationSection(kind: kind, title: title, count: 0, skills: [])
    }

    @Test func globalSectionCoversGlobalAndMultiAgent() {
        let kinds = SectionSelection.kinds(for: section(.global, "全局"))
        #expect(kinds == Set<ScopeKind>([.global, .multiAgent]))
    }

    @Test func projectSectionMapsToProjectKind() {
        #expect(SectionSelection.kinds(for: section(.project, "atlas")) == Set<ScopeKind>([.project]))
    }

    @Test func toggleSelectsThenDeselects() {
        let global = section(.global, "全局")
        #expect(SectionSelection.toggle(current: [], section: global) == Set<ScopeKind>([.global, .multiAgent]))
        #expect(SectionSelection.toggle(current: Set<ScopeKind>([.global, .multiAgent]), section: global) == [])
        // 从项目切到全局
        #expect(SectionSelection.toggle(current: Set<ScopeKind>([.project]), section: global) == Set<ScopeKind>([.global, .multiAgent]))
    }

    @Test func scopeFilterWiresIntoListFilter() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home)) // 4 agentOnly + 1 global

        env.selectedScopes = Set<ScopeKind>([.global])
        #expect(SkillListCore.filter("", env).count == 1)

        env.selectedScopes = []
        #expect(SkillListCore.filter("", env).count == 5)
    }
}
