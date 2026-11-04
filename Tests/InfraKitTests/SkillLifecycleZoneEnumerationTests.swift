import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 生命周期区枚举不再依赖 agent 名单：任何 agent（内置/自定义）留下的条目都必须可见。
/// 回归：旧实现按 knownAgentIDs 遍历，qwen/cursor/自定义 agent 的条目在 UI 与 `ak disabled` 中不可见。
@Suite struct SkillLifecycleZoneEnumerationTests {
    private func makeSkillDir(_ home: URL, _ path: String) -> URL {
        let dir = home.appendingPathComponent(path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "---\nname: \(dir.lastPathComponent)\ndescription: t\n---\nbody"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }

    @Test func disabledEntriesVisibleWithoutKnownAgentList() throws {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        let base = home.appendingPathComponent(".agentkeeper", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        let skill = makeSkillDir(home, ".qwen/skills/alpha")
        try lifecycle.disable(agentID: "qwen", skillDirectory: skill)

        // 新实例不传任何名单（模拟旧默认值漏掉 qwen 的场景）
        let reloaded = SkillLifecycle(baseDirectory: base)
        let entries = try reloaded.disabledEntries()
        #expect(entries.map(\.record.name) == ["alpha"])
        #expect(entries[0].record.agentID == "qwen")
    }

    @Test func trashEntriesVisibleForCustomAgent() throws {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        let base = home.appendingPathComponent(".agentkeeper", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        let skill = makeSkillDir(home, ".windsurf/skills/beta")
        try lifecycle.moveToTrash(agentID: "windsurf", skillDirectory: skill)

        let reloaded = SkillLifecycle(baseDirectory: base)
        let entries = try reloaded.trashEntries()
        #expect(entries.map(\.record.name) == ["beta"])
        #expect(entries[0].record.agentID == "windsurf")
    }

    /// 显式传入的 knownAgentIDs 仍作兜底并集（不破坏旧 API 语义）。
    @Test func knownAgentIDsStillHonoredAsUnion() throws {
        let home = makeFakeHome(files: [])
        defer { cleanup(home) }
        let base = home.appendingPathComponent(".agentkeeper", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        let skill = makeSkillDir(home, ".pi/skills/gamma")
        try lifecycle.disable(agentID: "pi", skillDirectory: skill)

        let reloaded = SkillLifecycle(baseDirectory: base, knownAgentIDs: ["pi"])
        #expect(try reloaded.disabledEntries().count == 1)
    }
}
