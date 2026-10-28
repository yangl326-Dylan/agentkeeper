import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct TagStoreTests {
    private func makeStore(_ home: URL) -> TagStore {
        TagStore(directory: home.appendingPathComponent("ak", isDirectory: true))
    }

    @Test func assignmentRoundTripAndReload() throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let store = makeStore(home)
        store.addDefinition("写作")
        store.assign(tag: "写作", skillID: "/path/to/skill")
        store.assign(tag: "写作", skillID: "/path/to/other")
        store.addDefinition("实验")
        store.assign(tag: "实验", skillID: "/path/to/skill")

        // 重新加载（持久化生效；标签定义按 Unicode 排序）
        let reloaded = makeStore(home)
        #expect(reloaded.tags() == ["写作", "实验"])
        #expect(Set(reloaded.assignments(tag: "写作")) == ["/path/to/skill", "/path/to/other"])
        #expect(Set(reloaded.tags(forSkillID: "/path/to/skill")) == ["写作", "实验"])
    }

    @Test func unassignAndRemoveDefinition() throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let store = makeStore(home)
        store.addDefinition("写作")
        store.assign(tag: "写作", skillID: "/s1")
        store.addDefinition("删除我")
        store.assign(tag: "删除我", skillID: "/s1")

        store.unassign(tag: "写作", skillID: "/s1")
        #expect(store.assignments(tag: "写作").isEmpty)
        #expect(store.tags(forSkillID: "/s1") == ["删除我"])

        // 删除标签定义：同时清掉其全部关联
        store.removeDefinition("删除我")
        #expect(store.tags() == ["写作"])
        #expect(store.tags(forSkillID: "/s1").isEmpty)
    }

    @Test func renamePropagatesToAllAssignments() throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let store = makeStore(home)
        store.addDefinition("alter")
        store.assign(tag: "alter", skillID: "/s1")
        store.assign(tag: "alter", skillID: "/s2")

        store.rename("alter", to: "以旧换新")
        #expect(store.tags() == ["以旧换新"])
        #expect(Set(store.assignments(tag: "以旧换新")) == ["/s1", "/s2"])
        #expect(store.assignments(tag: "alter").isEmpty)
    }

    @Test func duplicateTagNamesCollapsed() throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let store = makeStore(home)
        store.addDefinition("写作")
        store.addDefinition("写作") // 幂等
        store.rename("写作", to: "写作") // 幂等
        #expect(store.tags() == ["写作"])
        #expect(store.assign(tag: "写作", skillID: "/s1") == true)
        #expect(store.assign(tag: "不存在的标签", skillID: "/s1") == false)
    }

    @Test func corruptFileSelfHealsWithBackup() throws {
        let home = makeFakeHome(files: ["dummy"])
        defer { cleanup(home) }
        let directory = home.appendingPathComponent("ak", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{broken json".write(to: directory.appendingPathComponent("tags.json"), atomically: true, encoding: .utf8)

        let store = TagStore(directory: directory)
        #expect(store.tags().isEmpty) // 自愈为空
        // 损坏文件有备份
        let backups = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        #expect(backups.contains { $0.lastPathComponent.hasPrefix("tags.json.corrupt-") })
        // 且继续可用
        store.addDefinition("新")
        store.assign(tag: "新", skillID: "/s")
        #expect(makeStore(home).assignments(tag: "新") == ["/s"])
    }
}
