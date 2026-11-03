import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// ak CLI：参数解析与输出格式（纯函数），集成用例跑真实扫描管线。
@Suite struct AKCLITests {
    private func skill(_ name: String, scope: SkillScope) -> Skill {
        Skill(
            id: "cli-\(name)",
            name: name,
            directory: URL(fileURLWithPath: "/tmp/\(name)"),
            scope: scope,
            sha256: "sha-\(name)",
            skillDescription: "desc of \(name)"
        )
    }

    // MARK: 参数解析

    @Test func parseKnownCommands() {
        #expect(AKCLI.parse([]) == .help)
        #expect(AKCLI.parse(["list"]) == .list)
        #expect(AKCLI.parse(["doctor"]) == .doctor)
        #expect(AKCLI.parse(["help"]) == .help)
        #expect(AKCLI.parse(["--help"]) == .help)
    }

    @Test func parseUnknownCommand() {
        #expect(AKCLI.parse(["bogus"]) == .unknown("bogus"))
    }

    /// 生命周期子命令解析：disabled 无参；enable/restore/purge 恰需一个名字。
    @Test func parseLifecycleZoneCommands() {
        #expect(AKCLI.parse(["disabled"]) == .disabled)
        #expect(AKCLI.parse(["enable", "alpha"]) == .enable(name: "alpha"))
        #expect(AKCLI.parse(["restore", "alpha"]) == .restore(name: "alpha"))
        #expect(AKCLI.parse(["purge", "alpha"]) == .purge(name: "alpha"))
        // 缺名 / 多参都按未知命令退回（用法提示）
        #expect(AKCLI.parse(["enable"]) == .unknown("enable"))
        #expect(AKCLI.parse(["enable", "a", "b"]) == .unknown("enable"))
    }

    // MARK: 输出格式

    @Test func formatSkillsTableIsDeterministic() {
        let output = AKCLI.formatSkills([
            skill("zeta", scope: .global(owners: ["claude-code", "opencode"])),
            skill("alpha", scope: .agentOnly(agentID: "opencode")),
        ])
        let lines = output.split(separator: "\n").map(String.init)
        // 按 name 排序；列：NAME / SCOPE / AGENTS / PATH
        #expect(lines.count == 3) // 表头 + 2 行
        #expect(lines[0].contains("NAME"))
        #expect(lines[1].contains("alpha"))
        #expect(lines[1].contains("agent-only"))
        #expect(lines[1].contains("opencode"))
        #expect(lines[2].contains("zeta"))
        #expect(lines[2].contains("multi-agent") == false) // global 是共享
        #expect(lines[2].contains("claude-code,opencode"))
    }

    @Test func formatDoctorShowsInstalledAndMissing() {
        let output = AKCLI.formatDoctor([
            .init(id: "claude-code", name: "Claude Code", installed: true, skillCount: 12),
            .init(id: "qwen", name: "Qwen", installed: false, skillCount: 0),
        ])
        #expect(output.contains("claude-code"))
        #expect(output.contains("installed"))
        #expect(output.contains("qwen"))
        #expect(output.contains("not installed"))
        #expect(output.contains("12"))
    }

    // MARK: 集成（真实扫描管线 + 假 home）

    @Test func runListOnFakeHome() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-cli-\(UUID().uuidString)", isDirectory: true)
        let skillsDir = home.appendingPathComponent(".claude/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: test\n---\nbody".write(
            to: skillsDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let result = await AKCLI.run(["list"], homeDirectory: home)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("demo"))
        #expect(result.output.contains("claude-code"))
    }

    @Test func runDoctorOnFakeHomeCountsSkills() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-cli-\(UUID().uuidString)", isDirectory: true)
        let skillsDir = home.appendingPathComponent(".claude/skills/demo", isDirectory: true)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        try "---\nname: demo\ndescription: test\n---\nbody".write(
            to: skillsDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        defer { try? FileManager.default.removeItem(at: home) }

        let result = await AKCLI.run(["doctor"], homeDirectory: home)
        #expect(result.exitCode == 0)
        let line = result.output.split(separator: "\n").first { $0.contains("claude-code") } ?? ""
        #expect(String(line).contains("1")) // skill 数必须真实统计，不是 0
    }

    @Test func unknownCommandExitsNonZero() async throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let result = await AKCLI.run(["bogus"], homeDirectory: home)
        #expect(result.exitCode == 2)
        #expect(result.output.contains("bogus"))
        #expect(result.output.contains("ak --help"))
    }
}

// MARK: 生命周期区子命令（disabled / enable / restore / purge）

@Suite struct AKCLILifecycleZoneTests {
    private func makeSkill(_ home: URL, _ path: String) -> URL {
        let dir = home.appendingPathComponent(path, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! "---\nname: x\ndescription: 测试\n---\nA".write(
            to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        return dir
    }

    @Test func disabledListsBothZonesWithMarkers() async throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let lifecycle = SkillLifecycle(baseDirectory: home.appendingPathComponent(".agentkeeper"))
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: makeSkill(home, ".claude/skills/paused-one"))
        _ = try lifecycle.moveToTrash(agentID: "codex", skillDirectory: makeSkill(home, ".codex/skills/deleted-one"))

        let result = await AKCLI.run(["disabled"], homeDirectory: home)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("paused-one"))
        #expect(result.output.contains("deleted-one"))
        // 两个分区都有可读标记（ discharged 停用 / 回收站），agent 归属可见
        #expect(result.output.lowercased().contains("停用"))
        #expect(result.output.lowercased().contains("回收站"))
        #expect(result.output.contains("claude-code"))
    }

    @Test func enableRestoresDisabledByName() async throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let source = makeSkill(home, ".claude/skills/paused-two")
        let lifecycle = SkillLifecycle(baseDirectory: home.appendingPathComponent(".agentkeeper"))
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: source)

        let result = await AKCLI.run(["enable", "paused-two"], homeDirectory: home)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("恢复") || result.output.contains("启用"))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
    }

    /// 同名多副本（多 agent 各Paused 一份）时明确拒绝歧义，列出候选让用户选——CLI 不猜。
    @Test func enableRejectsAmbiguousDuplicateNames() async throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let lifecycle = SkillLifecycle(baseDirectory: home.appendingPathComponent(".agentkeeper"))
        _ = try lifecycle.disable(agentID: "claude-code", skillDirectory: makeSkill(home, ".claude/skills/dup"))
        _ = try lifecycle.disable(agentID: "opencode", skillDirectory: makeSkill(home, ".opencode/skills/dup"))

        let result = await AKCLI.run(["enable", "dup"], homeDirectory: home)
        #expect(result.exitCode == 1)
        #expect(result.output.contains("歧义") || result.output.contains("多个"))
        #expect(result.output.contains("claude-code"))
        #expect(result.output.contains("opencode"))
        // 两个副本都没动
        #expect(try lifecycle.disabledEntries().count == 2)
    }

    @Test func restoreBringsTrashEntryBack() async throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let source = makeSkill(home, ".opencode/skills/trashed-three")
        let lifecycle = SkillLifecycle(baseDirectory: home.appendingPathComponent(".agentkeeper"))
        _ = try lifecycle.moveToTrash(agentID: "opencode", skillDirectory: source)

        let result = await AKCLI.run(["restore", "trashed-three"], homeDirectory: home)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("回收站") || result.output.contains("恢复"))
        #expect(FileManager.default.fileExists(atPath: source.appendingPathComponent("SKILL.md").path))
    }

    @Test func purgeRemovesTrashEntryPermanently() async throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let lifecycle = SkillLifecycle(baseDirectory: home.appendingPathComponent(".agentkeeper"))
        _ = try lifecycle.moveToTrash(agentID: "opencode", skillDirectory: makeSkill(home, ".opencode/skills/to-purge"))

        let result = await AKCLI.run(["purge", "to-purge"], homeDirectory: home)
        #expect(result.exitCode == 0)
        #expect(result.output.contains("彻底删除"))
        #expect(try lifecycle.trashEntries().isEmpty)
    }

    @Test func unknownSkillNameExitsNonZero() async throws {
        let home = makeFakeHome(files: [], fileContents: [:])
        defer { cleanup(home) }
        let result = await AKCLI.run(["enable", "missing-skill"], homeDirectory: home)
        #expect(result.exitCode == 1)
        #expect(result.output.contains("missing-skill") || result.output.contains("未找到"))
    }
}
