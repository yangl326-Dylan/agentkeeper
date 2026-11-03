import Foundation
import Testing
import DomainKit
import AppCore
import InfraKit
@testable import AgentKeeperUI

/// 生命周期区流（env 层 E2E）：详情页删除 → 回收站行 → 恢复/彻底删除 →行清空。
@MainActor
@Suite struct LifecycleZoneFlowTests {
    private func makeHome() -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-zone-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeSkillDirectory(home: URL, agentSkillPath: String) -> URL {
        let dir = home.appendingPathComponent(agentSkillPath, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! "---\nname: probe\ndescription: e2e\n---\nA".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        return dir
    }

    private func makeSkill(id: String, name: String, directory: URL) -> Skill {
        Skill(
            id: id,
            name: name,
            directory: directory,
            scope: .agentOnly(agentID: "claude-code"),
            sha256: "sha-\(name)"
        )
    }

    /// 详情页「移入回收站」全链：操作 → 区行 bump 可见；恢复 → 原路径回位、行清空。
    @Test func deleteToTrashThenRestoreFromZone() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = makeSkillDirectory(home: home, agentSkillPath: ".claude/skills/probe")
        let env = AppEnvironment(homeDirectory: home)
        let skill = makeSkill(id: "probe|claude-code", name: "probe", directory: directory)
        env.catalogStore.sync(with: [skill])
        #expect(env.trashedZoneRows().isEmpty)

        await env.runOperation(skill: skill, direction: .delete)

        // 删除语义 = 移入回收站：原位消失、区行（自动 bump 后）可见
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        let trashRows = env.trashedZoneRows()
        #expect(trashRows.count == 1)
        #expect(trashRows[0].name == "probe")
        #expect(trashRows[0].agentID == "claude-code")

        // 恢复：原路径放回；行清空、停用区不掺入
        await env.enableFromZone(zone: .trash, row: trashRows[0])
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("SKILL.md").path))
        #expect(env.trashedZoneRows().isEmpty)
        #expect(env.disabledZoneRows().isEmpty)
    }

    /// 停用区全链：停用 → 区行可见；启用 → 回原路径。
    @Test func disableThenEnableThroughZoneRows() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = makeSkillDirectory(home: home, agentSkillPath: ".claude/skills/paused")
        let env = AppEnvironment(homeDirectory: home)
        let skill = makeSkill(id: "paused|claude-code", name: "paused", directory: directory)

        await env.runOperation(skill: skill, direction: .disable)

        let rows = env.disabledZoneRows()
        #expect(rows.count == 1)
        #expect(rows[0].name == "paused")

        await env.enableFromZone(zone: .disabled, row: rows[0])
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("SKILL.md").path))
        #expect(env.disabledZoneRows().isEmpty)
    }

    /// 彻底删除流程：行消失、磁盘条目消失、原路径仍不存在（不留半态）。
    @Test func purgeTrashEntryIsTerminal() async throws {
        let home = makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = makeSkillDirectory(home: home, agentSkillPath: ".claude/skills/gone")
        let env = AppEnvironment(homeDirectory: home)
        let skill = makeSkill(id: "gone|claude-code", name: "gone", directory: directory)

        await env.runOperation(skill: skill, direction: .delete)
        let row = try #require(env.trashedZoneRows().first)

        await env.purgeTrashEntry(row)

        #expect(env.trashedZoneRows().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!FileManager.default.fileExists(
            atPath: home.appendingPathComponent(".agentkeeper/trash/claude-code").path
        ))
    }
}
