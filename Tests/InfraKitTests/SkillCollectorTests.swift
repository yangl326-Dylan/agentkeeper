import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// DeepSeek Harness 扁平 skill 收集：root 直属 `<name>.md`；子目录内扁平不收（spec 2026-11-09）。
@Suite struct SkillCollectorFlatTests {
    @Test func collectsRootFlatMdAndSkipsNested() {
        let home = makeFakeHome(
            files: [
                ".dsh/skills/top.md",
                ".dsh/skills/nested/inner.md",
                ".dsh/skills/.hidden.md",
                ".dsh/skills/ignored.txt",
                ".dsh/skills/SKILL.md",
            ],
            fileContents: [
                ".dsh/skills/top.md": "---\nname: top\ndescription: t\n---\nT",
                ".dsh/skills/nested/inner.md": "---\nname: inner\ndescription: i\n---\nI",
                ".dsh/skills/.hidden.md": "h",
                ".dsh/skills/ignored.txt": "x",
                ".dsh/skills/SKILL.md": "s",
            ]
        )
        defer { cleanup(home) }
        let root = home.appendingPathComponent(".dsh/skills", isDirectory: true)
        let parsed = SkillCollector().collect(inRoot: root, agentID: "deepseek")
        let flatNames = parsed.filter { $0.isFlatFile }.map { $0.frontmatterName ?? "" }
        // root 直属 top.md 收集；nested/inner.md、隐藏、非 md、游离根级 SKILL.md 均不收
        #expect(flatNames == ["top"])
    }

    @Test func flatAndPackageCoexist() {
        let home = makeFakeHome(
            files: [
                ".dsh/skills/pack/SKILL.md",
                ".dsh/skills/pack.md",
            ],
            fileContents: [
                ".dsh/skills/pack/SKILL.md": "---\nname: pack\ndescription: pkg\n---\nP",
                ".dsh/skills/pack.md": "---\nname: pack\ndescription: flat\n---\nF",
            ]
        )
        defer { cleanup(home) }
        let root = home.appendingPathComponent(".dsh/skills", isDirectory: true)
        let parsed = SkillCollector().collect(inRoot: root, agentID: "deepseek")
        #expect(parsed.count == 2)
        #expect(parsed.filter { !$0.isFlatFile }.first?.frontmatterDescription == "pkg")
        #expect(parsed.filter { $0.isFlatFile }.first?.frontmatterDescription == "flat")
    }
}

@Suite struct SkillCollectorTests {
    @Test func recursiveDiscoveryAtAnyDepth() {
        let home = makeFakeHome(
            files: [
                "root/shallow/SKILL.md",
                "root/deep/nested/impl/SKILL.md",
            ],
            fileContents: [
                "root/shallow/SKILL.md": "---\nname: shallow\ndescription: 浅层\n---\nA",
                "root/deep/nested/impl/SKILL.md": "---\nname: deep\ndescription: 深层\n---\nB",
            ]
        )
        defer { cleanup(home) }
        let root = home.appendingPathComponent("root", isDirectory: true)
        let collector = SkillCollector()
        let skills = collector.collect(inRoot: root, agentID: "claude-code")
        #expect(skills.count == 2)
        let names = Set(skills.compactMap(\.frontmatterName))
        #expect(names == ["shallow", "deep"])
    }

    @Test func directoriesWithoutSKILLMdAreIgnoredNotError() {
        let home = makeFakeHome(files: [
            "root/docs/readme.md",
            "root/assets/pic.png",
        ])
        defer { cleanup(home) }
        let collector = SkillCollector()
        let skills = collector.collect(inRoot: home.appendingPathComponent("root", isDirectory: true), agentID: "claude-code")
        #expect(skills.isEmpty)
    }

    @Test func hiddenDirectoriesAreSkipped() {
        let home = makeFakeHome(files: [
            "root/.hidden/SKILL.md",
            "root/visible/SKILL.md",
        ])
        defer { cleanup(home) }
        let collector = SkillCollector()
        let skills = collector.collect(inRoot: home.appendingPathComponent("root", isDirectory: true), agentID: "claude-code")
        #expect(skills.count == 1)
        #expect(skills[0].directory.lastPathComponent == "visible")
    }
}
