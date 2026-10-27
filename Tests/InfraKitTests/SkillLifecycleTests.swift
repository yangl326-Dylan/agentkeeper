import Foundation
import Testing
import DomainKit
@testable import InfraKit

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
