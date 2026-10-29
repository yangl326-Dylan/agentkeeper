import Foundation
import Testing
import DomainKit
import AppCore
@testable import AgentKeeperUI

/// 侧栏导航选择切换语义（Agents / Skills 节 / 标签共用同一套规则）。
@Suite struct SelectionToggleTests {
    @Test func toggleByType() {
        // agent 字符串
        #expect(SelectionToggle.toggle(current: nil, clicked: "opencode") == "opencode")
        // 再点同项取消
        #expect(SelectionToggle.toggle(current: "opencode", clicked: "opencode") == nil)
        // 异项切换
        #expect(SelectionToggle.toggle(current: "opencode", clicked: "claude-code") == "claude-code")
        // 标签同套
        #expect(SelectionToggle.toggle(current: "写作", clicked: "写作") == nil)
    }

    @MainActor
    @Test func tagCancelRestoresUnfiltered() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)
        env.catalogStore.sync(with: UIWiring.demoSkills(home: home))
        let target = env.catalogStore.current.first { $0.name == "review" }!
        env.tagService.addTag("写作", toSkillID: target.id)

        env.selectedTag = "写作"
        #expect(SkillListCore.filter("", env).count == 1)
        // 再点同标签 → 取消筛选 ↔ 全量最小视图（未加作用域/agent 筛）
        env.selectedTag = SelectionToggle.toggle(current: env.selectedTag, clicked: "写作")
        #expect(env.selectedTag == nil)
        #expect(SkillListCore.filter("", env).count == 5)
    }
}
