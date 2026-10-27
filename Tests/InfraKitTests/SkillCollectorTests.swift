import Foundation
import Testing
import DomainKit
@testable import InfraKit

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
