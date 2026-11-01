import Foundation
import Testing
import DomainKit
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
