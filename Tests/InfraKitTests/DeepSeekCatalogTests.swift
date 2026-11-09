import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// deepseek 收录后的 catalog 链路：双形态扫描 + layout 标注（spec 2026-11-09）。
@Suite struct DeepSeekCatalogTests {
    private func agent(_ id: AgentID, roots: [SkillRoot]) -> Agent {
        Agent(id: id, name: id, installState: .installed(configDirectory: nil), skillRoots: roots)
    }

    @Test func catalogMarksFlatLayout() throws {
        let home = makeFakeHome(
            files: [
                ".dsh/skills/pack/SKILL.md",
                ".dsh/skills/flat-one.md",
            ],
            fileContents: [
                ".dsh/skills/pack/SKILL.md": "---\nname: pack\ndescription: pkg\n---\nP",
                ".dsh/skills/flat-one.md": "---\nname: flat-one\ndescription: flat\n---\nF",
            ]
        )
        defer { cleanup(home) }
        let root = SkillRoot(
            path: home.appendingPathComponent(".dsh/skills", isDirectory: true),
            owners: ["deepseek"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("deepseek", roots: [root])])
        #expect(skills.count == 2)
        let flat = try #require(skills.first { $0.layout == .flatFile })
        #expect(flat.name == "flat-one")
        #expect(flat.skillDescription == "flat")
        guard case let .agentOnly(owner) = flat.scope else {
            Issue.record("expected agentOnly, got \(flat.scope)")
            return
        }
        #expect(owner == "deepseek")
        #expect(skills.first { $0.layout == .directoryPackage }?.name == "pack")
    }
}
