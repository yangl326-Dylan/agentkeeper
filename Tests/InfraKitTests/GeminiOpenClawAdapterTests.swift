import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct GeminiAdapterTests {
    @Test func detectInstalledFromDotGemini() async {
        let home = makeFakeHome(files: [".gemini/settings.json"])
        defer { cleanup(home) }
        let adapter = GeminiAdapter(homeDirectory: home)
        guard case .installed = await adapter.detectInstallation() else {
            Issue.record("expected installed")
            return
        }
    }

    @Test func detectNotInstalled() async {
        let home = makeFakeHome(files: ["z.txt"])
        defer { cleanup(home) }
        let adapter = GeminiAdapter(homeDirectory: home)
        #expect(await adapter.detectInstallation() == .notInstalled)
    }

    @Test func skillRootReportedWhenSkillsDirExists() async {
        let home = makeFakeHome(files: [".gemini/skills/refactor/SKILL.md"])
        defer { cleanup(home) }
        let adapter = GeminiAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.count == 1)
        #expect(roots[0].owners == ["gemini"])
    }
}

@Suite struct OpenClawAdapterTests {
    @Test func detectInstalledFromOpenClawDir() async {
        let home = makeFakeHome(files: [".openclaw/openclaw.json"])
        defer { cleanup(home) }
        let adapter = OpenClawAdapter(homeDirectory: home)
        guard case .installed = await adapter.detectInstallation() else {
            Issue.record("expected installed")
            return
        }
    }

    @Test func detectNotInstalled() async {
        let home = makeFakeHome(files: ["w.txt"])
        defer { cleanup(home) }
        let adapter = OpenClawAdapter(homeDirectory: home)
        #expect(await adapter.detectInstallation() == .notInstalled)
    }

    @Test func reportsWorkspaceAndGlobalSkillRoots() async {
        // OpenClaw：`~/.openclaw/skills`（全局）与 `~/.openclaw/workspace/skills`（工作区）双候选
        let home = makeFakeHome(files: [
            ".openclaw/openclaw.json",
            ".openclaw/skills/one/SKILL.md",
            ".openclaw/workspace/skills/two/SKILL.md",
        ])
        defer { cleanup(home) }
        let adapter = OpenClawAdapter(homeDirectory: home)
        let roots = await adapter.skillRoots()
        #expect(roots.count == 2)
        #expect(roots.allSatisfy { $0.owners == ["openclaw"] })
    }

    @Test func parseWorkspaceSkill() async {
        let home = makeFakeHome(
            files: [".openclaw/workspace/skills/keep-notes/SKILL.md"],
            fileContents: [".openclaw/workspace/skills/keep-notes/SKILL.md": "---\nname: keep-notes\ndescription: 备忘\n---\nBody"]
        )
        defer { cleanup(home) }
        let adapter = OpenClawAdapter(homeDirectory: home)
        let parsed = await adapter.parseSkill(at: home.appendingPathComponent(".openclaw/workspace/skills/keep-notes", isDirectory: true))
        #expect(parsed?.frontmatterName == "keep-notes")
    }
}
