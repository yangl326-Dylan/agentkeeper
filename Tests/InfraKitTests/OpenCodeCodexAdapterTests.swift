import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct OpenCodeAdapterTests {
    @Test func detectInstalledFromConfigDirectory() async {
        let home = makeFakeHome(files: [".config/opencode/opencode.jsonc"])
        defer { cleanup(home) }
        let adapter = OpenCodeAdapter(homeDirectory: home)
        guard case .installed = await adapter.detectInstallation() else {
            Issue.record("expected installed")
            return
        }
    }

    @Test func detectNotInstalled() async {
        let home = makeFakeHome(files: ["x.txt"])
        defer { cleanup(home) }
        let adapter = OpenCodeAdapter(homeDirectory: home)
        #expect(await adapter.detectInstallation() == .notInstalled)
    }

    @Test func skillRootPicksExistingCandidateAmongSingularPlural() async {
        // opencode 约定可能是 `skill` 或 `skills`，只报告实际存在者
        let home = makeFakeHome(files: [".config/opencode/skill/demo/SKILL.md"])
        defer { cleanup(home) }
        let adapter = OpenCodeAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.count == 1)
        #expect(roots[0].path == home.appendingPathComponent(".config/opencode/skill", isDirectory: true))
        #expect(roots[0].owners == ["opencode"])
    }

    @Test func parseStandardSKILLMd() async {
        let home = makeFakeHome(
            files: [".config/opencode/skill/demo/SKILL.md"],
            fileContents: [".config/opencode/skill/demo/SKILL.md": "---\nname: demo-op\ndescription: opencode 测试\n---\nbody"]
        )
        defer { cleanup(home) }
        let adapter = OpenCodeAdapter(homeDirectory: home)
        let parsed = await adapter.parseSkill(at: home.appendingPathComponent(".config/opencode/skill/demo", isDirectory: true))
        #expect(parsed?.frontmatterName == "demo-op")
    }
}

@Suite struct CodexAdapterTests {
    @Test func detectInstalledFromDotCodex() async {
        let home = makeFakeHome(files: [".codex/config.toml"])
        defer { cleanup(home) }
        let adapter = CodexAdapter(homeDirectory: home)
        guard case .installed = await adapter.detectInstallation() else {
            Issue.record("expected installed")
            return
        }
    }

    @Test func detectNotInstalled() async {
        let home = makeFakeHome(files: ["y.txt"])
        defer { cleanup(home) }
        let adapter = CodexAdapter(homeDirectory: home)
        #expect(await adapter.detectInstallation() == .notInstalled)
    }

    @Test func skillRootEmptyWhenNoSkillDirectoryYet() async {
        let home = makeFakeHome(files: [".codex/config.toml"])
        defer { cleanup(home) }
        let adapter = CodexAdapter(homeDirectory: home)
        #expect(await adapter.skillRoots().isEmpty)
    }

    @Test func skillRootFoundWhenSkillsExist() async {
        let home = makeFakeHome(files: [".codex/skills/alpha/SKILL.md"])
        defer { cleanup(home) }
        let adapter = CodexAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.count == 1)
        #expect(roots[0].owners == ["codex"])
    }
}
