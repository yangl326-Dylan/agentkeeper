import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 5.3/5.4：TagService 标签编排与 orphan 检测。
@Suite struct TagServiceTests {
    private func makeService(_ base: URL) -> (TagService, TagStore) {
        let store = TagStore(directory: base.appendingPathComponent("ak", isDirectory: true))
        // true disabledRoot：ak/disabled（orphan 判定要排除禁用关联）
        let service = TagService(
            store: store,
            disabledRoot: base.appendingPathComponent("ak/disabled", isDirectory: true)
        )
        return (service, store)
    }

    @Test func addTagCreatesDefinitionAndAssigns() {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let (service, _) = makeService(home)
        service.addTag("写作", toSkillID: "/s1")
        service.addTag("写作", toSkillID: "/s2")
        #expect(service.tags() == ["写作"])
        #expect(Set(service.assignments(tag: "写作")) == ["/s1", "/s2"])
    }

    @Test func deleteTagTouchesOnlyTagLayer() {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let (service, _) = makeService(home)
        service.addTag("写作", toSkillID: "/s1")
        service.deleteTag("写作")
        #expect(service.tags().isEmpty)
        #expect(service.tags(forSkillID: "/s1").isEmpty)
    }

    @Test func renameTagAppliesToAllAssignments() {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let (service, _) = makeService(home)
        service.addTag("写作", toSkillID: "/s1")
        service.addTag("写作", toSkillID: "/s2")
        service.renameTag("写作", to: "以旧换新")
        #expect(service.tags() == ["以旧换新"])
        #expect(Set(service.assignments(tag: "以旧换新")) == ["/s1", "/s2"])
    }

    /// orphan：catalog 无该 skill 且不在禁用区 → 计数 +1，可清除。
    @Test func orphanDetectionCountsMissingNonDisabledSkills() {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let (service, _) = makeService(home)
        let disabledSkillPath = home.appendingPathComponent("ak/disabled/codex/review", isDirectory: true).path
        service.addTag("写作", toSkillID: "/gone")
        service.addTag("写作", toSkillID: disabledSkillPath) // 禁用区：不算 orphan
        let alive = Skill(
            id: "/alive",
            name: "alive",
            directory: URL(fileURLWithPath: "/alive", isDirectory: true),
            scope: .agentOnly(agentID: "claude-code"),
            sha256: "x"
        )
        #expect(service.orphanCount(catalog: [alive]) == 1)
        let removed = service.purgeOrphans(catalog: [alive])
        #expect(removed == 1)
        #expect(service.orphanCount(catalog: [alive]) == 0)
        // 禁用区关联保留
        #expect(service.assignments(tag: "写作").contains(disabledSkillPath))
    }
}
