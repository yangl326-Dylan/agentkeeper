import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 崩溃与损坏恢复演练（7.3）：手删 ~/.agentkeeper 子树、损坏 SQLite、中断搬移。
@Suite struct RecoveryDrillTests {
    @Test func homeSubtreeDeletionRecoversByRebuild() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-drill-\(UUID().uuidString)", isDirectory: true)
        // 先有历史
        do {
            let index = SkillIndex(databaseDirectory: base)
            index.replaceAll([
                Skill(id: "x|a", name: "x", directory: URL(fileURLWithPath: "/tmp/x"), scope: .agentOnly(agentID: "a"), sha256: "s"),
            ])
            let history = OperationHistory(directory: base)
            history.append(skillID: "x|a", name: "x", direction: .disable, result: .success)
        }
        // 手删全部子树
        try FileManager.default.removeItem(at: base)

        // 重建后 UI 组件全部可用（空、完整、可写）
        let index = SkillIndex(databaseDirectory: base)
        #expect(index.integrity())
        #expect(index.all().isEmpty)
        index.upsert([
            Skill(id: "y|a", name: "y", directory: URL(fileURLWithPath: "/tmp/y"), scope: .agentOnly(agentID: "a"), sha256: "s"),
        ])
        #expect(index.all().count == 1)

        let history = OperationHistory(directory: base)
        #expect(history.recent(limit: 10).isEmpty)
        history.append(skillID: "y|a", name: "y", direction: .enable, result: .success)
        #expect(history.recent(limit: 10).count == 1)
    }

    @Test func interruptedDisableLeavesUnknownDisabledEntryNeverAutoDelete() throws {
        let home = makeFakeHome(files: [".claude/skills/alpha/SKILL.md"])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)

        // 模拟 kill -9：目录已被搬入禁用区，但 manifest 未写
        let disabledDir = base.appendingPathComponent("disabled/claude-code/alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: disabledDir, withIntermediateDirectories: true)
        try "---\nname: alpha\ndescription: d\n---\nA".write(to: disabledDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        // 重启后：未知禁用目录被摆上台面（供 UI 引导），绝不自动删除
        let unknown = lifecycle.unknownDisabledEntries()
        #expect(unknown.count == 1)
        #expect(unknown[0].agentID == "claude-code")
        #expect(unknown[0].name == "alpha")
        #expect(FileManager.default.fileExists(atPath: disabledDir.appendingPathComponent("SKILL.md").path))
    }

    @Test func interruptedEnableCleanupOrphanManifestsIdempotent() throws {
        let home = makeFakeHome(
            files: [".claude/skills/alpha/SKILL.md"],
            fileContents: [".claude/skills/alpha/SKILL.md": "---\nname: alpha\ndescription: d\n---\nA"]
        )
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: home.appendingPathComponent(".claude/skills/alpha", isDirectory: true))

        // 模拟 kill -9 发生在恢复 success 通道："搬回原路径已完成、manifest 删除未执行"：
        // 禁用目录已消失、manifest 残留 → 幂等清理把 manifest 清掉（内容已在原位，零丢失）
        try FileManager.default.removeItem(at: base.appendingPathComponent("disabled/claude-code/alpha"))
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".claude/skills/alpha"), withIntermediateDirectories: true)
        try "---\nname: alpha\ndescription: d\n---\nA".write(
            to: home.appendingPathComponent(".claude/skills/alpha/SKILL.md"),
            atomically: true,
            encoding: .utf8
        )
        let removed = try lifecycle.cleanupOrphanManifests()
        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("disabled/claude-code/alpha.manifest.json").path))
        // 幂等：再清一次为 0
        #expect(try lifecycle.cleanupOrphanManifests() == 0)
        // 原位内容完好
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude/skills/alpha/SKILL.md").path))
    }
}
