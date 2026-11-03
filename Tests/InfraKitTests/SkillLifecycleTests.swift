import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SkillLifecycleEnableTests {
    private func makeEnvironment() -> (home: URL, base: URL) {
        let home = makeFakeHome(
            files: [".claude/skills/alpha/SKILL.md", ".claude/skills/alpha/scripts/run.sh"],
            fileContents: [
                ".claude/skills/alpha/SKILL.md": "---\nname: alpha\ndescription: 测试\n---\nA",
                ".claude/skills/alpha/scripts/run.sh": "#!/bin/sh\n",
            ]
        )
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        return (home, base)
    }

    @Test func enableRestoresToOriginalPathAndClearsManifest() throws {
        let (home, base) = makeEnvironment()
        defer { cleanup(home) }
        let source = home.appendingPathComponent(".claude/skills/alpha", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: source)

        let record = try lifecycle.enable(agentID: "claude-code", name: "alpha")

        #expect(record.originalPath == source.path)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("scripts/run.sh").path))
        // manifest 已清理（不留垃圾）
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("disabled/claude-code/alpha.manifest.json").path))
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("disabled/claude-code/alpha").path))
    }

    @Test func enableWithoutDisableManifestIsRejected() throws {
        let (home, base) = makeEnvironment()
        defer { cleanup(home) }
        let lifecycle = SkillLifecycle(baseDirectory: base)
        #expect(throws: SkillLifecycleError.self) {
            try lifecycle.enable(agentID: "claude-code", name: "never-disabled")
        }
    }

    @Test func enableOriginalPathOccupiedAbortsWithConflictDetail() throws {
        let (home, base) = makeEnvironment()
        defer { cleanup(home) }
        let source = home.appendingPathComponent(".claude/skills/alpha", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: source)

        // 原路径被外部重新创建（agent 又装了同名 skill / 手动残留）
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try "native new version".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        #expect(throws: SkillLifecycleError.self) {
            try lifecycle.enable(agentID: "claude-code", name: "alpha")
        }
        // 冲突中止：禁用区份与原路径的原生新版本都完好，绝不覆盖
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("disabled/claude-code/alpha").path))
        #expect(try String(contentsOf: source.appendingPathComponent("SKILL.md"), encoding: .utf8) == "native new version")
    }
}

@Suite struct SkillLifecycleDisableTests {
    private func makeEnvironment() -> (home: URL, base: URL) {
        let home = makeFakeHome(
            files: [".claude/skills/alpha/SKILL.md", ".claude/skills/alpha/scripts/run.sh"],
            fileContents: [
                ".claude/skills/alpha/SKILL.md": "---\nname: alpha\ndescription: 测试\n---\nA",
                ".claude/skills/alpha/scripts/run.sh": "#!/bin/sh\n",
            ]
        )
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        return (home, base)
    }

    @Test func disableMovesSkillIntoDisabledAreaAndRecordsManifest() throws {
        let (home, base) = makeEnvironment()
        defer { cleanup(home) }
        let source = home.appendingPathComponent(".claude/skills/alpha", isDirectory: true)

        let lifecycle = SkillLifecycle(baseDirectory: base)
        let record = try lifecycle.disable(agentID: "claude-code", skillDirectory: source)

        // 记录字段齐全（恢复 4.3 全部依赖这里）
        #expect(record.agentID == "claude-code")
        #expect(record.originalPath == source.path)
        #expect(record.name == "alpha")
        #expect(!record.sha256.isEmpty)

        // 目录进入统一禁用区：~/.agentkeeper/disabled/<agent>/<skill>
        let disabledDir = base.appendingPathComponent("disabled/claude-code/alpha", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: disabledDir.appendingPathComponent("SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: disabledDir.appendingPathComponent("scripts/run.sh").path))
        #expect(!FileManager.default.fileExists(atPath: source.path))

        // manifest 是禁用目录旁边的兄弟文件
        let manifestURL = base.appendingPathComponent("disabled/claude-code/alpha.manifest.json")
        let manifestData = try Data(contentsOf: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(DisabledSkillRecord.self, from: manifestData)
        #expect(manifest.originalPath == source.path)
        #expect(manifest.agentID == "claude-code")
    }

    @Test func disableTwiceIsRejectedAndSourceStaysIntact() throws {
        let (home, base) = makeEnvironment()
        defer { cleanup(home) }
        let source = home.appendingPathComponent(".claude/skills/alpha", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: source)

        // 源已搬空；再次 disable 同路径应体面拒绝（不是崩溃）
        #expect(throws: (any Error).self) {
            try lifecycle.disable(agentID: "claude-code", skillDirectory: source)
        }
    }

    @Test func disableDestinationOccupiedAbortsAndNeverOverwrites() throws {
        let (home, base) = makeEnvironment()
        defer { cleanup(home) }
        let source = home.appendingPathComponent(".claude/skills/alpha", isDirectory: true)
        // 预占禁用区目标
        let occupied = base.appendingPathComponent("disabled/claude-code/alpha", isDirectory: true)
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        try "existing".write(to: occupied.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let lifecycle = SkillLifecycle(baseDirectory: base)
        #expect(throws: SkillLifecycleError.self) {
            try lifecycle.disable(agentID: "claude-code", skillDirectory: source)
        }
        // 冲突中止：源完好（绝不覆盖）
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
        #expect(try String(contentsOf: occupied.appendingPathComponent("SKILL.md"), encoding: .utf8) == "existing")
    }
}

// MARK: - 回收站区（trash）：删除入站可回滚 + 永久清除

@Suite struct SkillLifecycleTrashTests {
    private func makeSkill(_ home: URL, path: String) -> URL {
        let dir = home.appendingPathComponent(path, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! "---\nname: x\ndescription: 测试\n---\nA".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        return dir
    }

    /// 删除语义 = 原样保全进回收站（trash/<agent>/<skill>/）+ manifest（原路径）——回滚依据零丢失。
    @Test func moveToTrashPreservesContentAndWritesManifest() throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let source = makeSkill(home, path: ".claude/skills/beta")
        let lifecycle = SkillLifecycle(baseDirectory: base)

        let record = try lifecycle.moveToTrash(agentID: "claude-code", skillDirectory: source)

        #expect(record.originalPath == source.path)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        let trashed = base.appendingPathComponent("trash/claude-code/beta/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("trash/claude-code/beta.manifest.json").path))
    }

    /// 列举：disabled 与 trash 各自出全表（agent 分组无所谓，扁平 + 记录足够 UI）。 
    @Test func entriesEnumerateManifestsAcrossBothZones() throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let disabledSource = makeSkill(home, path: ".claude/skills/enabled-one")
        let trashedSource = makeSkill(home, path: ".codex/skills/gone-two")
        let lifecycle = SkillLifecycle(baseDirectory: base)
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: disabledSource)
        _ = try lifecycle.moveToTrash(agentID: "codex", skillDirectory: trashedSource)

        let disabled = try lifecycle.disabledEntries()
        #expect(disabled.count == 1)
        #expect(disabled[0].record.name == "enabled-one")
        #expect(disabled[0].record.agentID == "claude-code")
        #expect(disabled[0].manifestPath.contains("disabled/claude-code"))

        let trashed = try lifecycle.trashEntries()
        #expect(trashed.count == 1)
        #expect(trashed[0].record.name == "gone-two")
        #expect(trashed[0].record.agentID == "codex")
        #expect(trashed[0].manifestPath.contains("trash/codex"))
    }

    /// 回收站恢复：按 manifest 原路径放回、manifest 清理；原路径被占 → 中止零覆盖。
    @Test func restoreFromTrashPutsBackAndRejectsOccupiedDestination() throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let source = makeSkill(home, path: ".claude/skills/gamma")
        let lifecycle = SkillLifecycle(baseDirectory: base)
        _ = try lifecycle.moveToTrash(agentID: "claude-code", skillDirectory: source)

        let record = try lifecycle.restoreFromTrash(agentID: "claude-code", name: "gamma")
        #expect(record.originalPath == source.path)
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("trash/claude-code").path))

        // 冲突分支：再次入站后原路径被占
        _ = try lifecycle.moveToTrash(agentID: "claude-code", skillDirectory: source)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        #expect(throws: SkillLifecycleError.self) {
            try lifecycle.restoreFromTrash(agentID: "claude-code", name: "gamma")
        }
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("trash/claude-code/gamma/SKILL.md").path))
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("trash/claude-code/gamma.manifest.json").path))
    }

    /// 彻底删除：单个清除（目录 + manifest 一并）；空 agent 目录顺手清。
    @Test func purgeTrashRemovesEntryAndRecording() throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let source = makeSkill(home, path: ".claude/skills/delta")
        let lifecycle = SkillLifecycle(baseDirectory: base)
        _ = try lifecycle.moveToTrash(agentID: "claude-code", skillDirectory: source)
        let other = makeSkill(home, path: ".codex/skills/keep")
        _ = try lifecycle.moveToTrash(agentID: "codex", skillDirectory: other)

        _ = try lifecycle.purgeTrash(agentID: "claude-code", name: "delta")

        #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("trash/claude-code").path))
        // 其它条目不受牵连
        #expect(FileManager.default.fileExists(atPath: base.appendingPathComponent("trash/codex/keep/SKILL.md").path))
    }

    /// 清空回收站：全部清除并返回数量；空回收站返回 0（幂等）。
    @Test func purgeAllTrashEmptiesZoneIdempotently() throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        let a = makeSkill(home, path: ".claude/skills/b1")
        _ = try lifecycle.moveToTrash(agentID: "claude-code", skillDirectory: a)
        let b = makeSkill(home, path: ".codex/skills/b2")
        _ = try lifecycle.moveToTrash(agentID: "codex", skillDirectory: b)

        #expect(try lifecycle.purgeAllTrash() == 2)
        #expect(try lifecycle.purgeAllTrash() == 0)
        #expect(try lifecycle.trashEntries().isEmpty)
    }
}
