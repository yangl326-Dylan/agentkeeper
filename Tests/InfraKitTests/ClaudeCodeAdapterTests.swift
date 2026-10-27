import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 为 adapter 测试构建临时"家目录"夹具。
@discardableResult
func makeFakeHome(
    files: [String],
    fileContents: [String: String] = [:]
) -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("ak-fixture-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    for relative in files {
        let target = home.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = fileContents[relative] ?? "placeholder\n"
        try? content.write(to: target, atomically: true, encoding: .utf8)
    }
    return home
}

func cleanup(_ home: URL) {
    try? FileManager.default.removeItem(at: home)
}

@Suite struct ClaudeCodeAdapterTests {
    @Test func detectsInstalledWhenClaudeDirExists() async {
        let home = makeFakeHome(files: [".claude/skills/dummy/SKILL.md"])
        defer { cleanup(home) }
        let adapter = ClaudeCodeAdapter(homeDirectory: home)
        let state = await adapter.detectInstallation()
        guard case .installed = state else {
            Issue.record("expected installed, got \(state)")
            return
        }
    }

    @Test func detectsNotInstalledWhenNoClaudeDir() async {
        let home = makeFakeHome(files: ["unrelated.txt"])
        defer { cleanup(home) }
        let adapter = ClaudeCodeAdapter(homeDirectory: home)
        let state = await adapter.detectInstallation()
        #expect(state == .notInstalled)
    }

    @Test func userLevelSkillRootReported() async {
        let home = makeFakeHome(files: [".claude/skills/dummy/SKILL.md"])
        defer { cleanup(home) }
        let adapter = ClaudeCodeAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.count == 1)
        #expect(roots[0].path == home.appendingPathComponent(".claude/skills", isDirectory: true))
        #expect(roots[0].owners == ["claude-code"])
        #expect(roots[0].level == .user)
    }

    @Test func parsesSkillWithFrontmatterAndNestedFiles() async {
        let home = makeFakeHome(
            files: [".claude/skills/alpha/SKILL.md", ".claude/skills/alpha/scripts/run.sh"],
            fileContents: [
                ".claude/skills/alpha/SKILL.md": """
                ---
                name: alpha-skill
                description: 测试用 skill
                ---
                # 正文
                """,
                ".claude/skills/alpha/scripts/run.sh": "#!/bin/sh\necho hi\n",
            ]
        )
        defer { cleanup(home) }
        let adapter = ClaudeCodeAdapter(homeDirectory: home)
        let directory = home.appendingPathComponent(".claude/skills/alpha", isDirectory: true)
        guard let parsed = await adapter.parseSkill(at: directory) else {
            Issue.record("expected parse")
            return
        }
        #expect(parsed.frontmatterName == "alpha-skill")
        #expect(parsed.frontmatterDescription == "测试用 skill")
        #expect(parsed.files.count == 2)
        #expect(!parsed.sha256.isEmpty)
    }

    @Test func directoryWithoutSkillMdReturnsNil() async {
        let home = makeFakeHome(files: [".claude/skills/empty/readme.md"])
        defer { cleanup(home) }
        let adapter = ClaudeCodeAdapter(homeDirectory: home)
        let directory = home.appendingPathComponent(".claude/skills/empty", isDirectory: true)
        let parsed = await adapter.parseSkill(at: directory)
        #expect(parsed == nil)
    }
}
