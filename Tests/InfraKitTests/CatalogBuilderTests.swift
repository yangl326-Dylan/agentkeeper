import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct CatalogBuilderScopeTests {
    private func agent(_ id: AgentID, roots: [SkillRoot]) -> Agent {
        Agent(id: id, name: id, installState: .installed(configDirectory: nil), skillRoots: roots)
    }

    @Test func privateRootYieldsAgentOnly() {
        let home = makeFakeHome(
            files: [".claude/skills/mine-only/SKILL.md"],
            fileContents: [".claude/skills/mine-only/SKILL.md": "---\nname: mine-only\ndescription: d\n---\nC"]
        )
        defer { cleanup(home) }
        let root = SkillRoot(
            path: home.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .user
        )
        let builder = CatalogBuilder()
        let skills = builder.build(agents: [agent("claude-code", roots: [root])])
        #expect(skills.count == 1)
        #expect(skills[0].scope == .agentOnly(agentID: "claude-code"))
        #expect(skills[0].projectTag() == nil)
    }

    @Test func sharedRootYieldsGlobalWithReasonCarryingOwners() {
        let home = makeFakeHome(
            files: ["shared/glow/SKILL.md"],
            fileContents: ["shared/glow/SKILL.md": "---\nname: glow\ndescription: 全局\n---\nC"]
        )
        defer { cleanup(home) }
        let root = SkillRoot(
            path: home.appendingPathComponent("shared", isDirectory: true),
            owners: ["claude-code", "opencode"],
            level: .user
        )
        let builder = CatalogBuilder()
        let skills = builder.build(agents: [agent("claude-code", roots: [root]), agent("opencode", roots: [])])
        #expect(skills.count == 1)
        guard case let .global(owners) = skills[0].scope else {
            Issue.record("expected global, got \(skills[0].scope)")
            return
        }
        #expect(Set(owners) == ["claude-code", "opencode"])
    }

    @Test func projectRootYieldsProjectScopeWithTagName() {
        let home = makeFakeHome(
            files: ["projects/atlas/.claude/skills/inner/SKILL.md"],
            fileContents: ["projects/atlas/.claude/skills/inner/SKILL.md": "---\nname: inner\ndescription: p\n---\nC"]
        )
        defer { cleanup(home) }
        let projectRoot = ProjectRoot(path: home.appendingPathComponent("projects/atlas", isDirectory: true))
        let root = SkillRoot(
            path: projectRoot.path.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .project(projectRoot)
        )
        let builder = CatalogBuilder()
        let skills = builder.build(agents: [agent("claude-code", roots: [root])])
        #expect(skills.count == 1)
        guard case let .project(agentID, root) = skills[0].scope else {
            Issue.record("expected project, got \(skills[0].scope)")
            return
        }
        #expect(agentID == "claude-code")
        #expect(root.tagName == "atlas")
    }

    @Test func identicalNameAndShaAcrossAgentDirsIsMultiAgent() {
        let home = makeFakeHome(
            files: [
                ".claude/skills/twin/SKILL.md",
                ".config/opencode/skill/twin/SKILL.md",
            ],
            fileContents: [
                ".claude/skills/twin/SKILL.md": "---\nname: twin\ndescription: 双份\n---\nSAME",
                ".config/opencode/skill/twin/SKILL.md": "---\nname: twin\ndescription: 双份\n---\nSAME",
            ]
        )
        defer { cleanup(home) }
        let claudeRoot = SkillRoot(path: home.appendingPathComponent(".claude/skills", isDirectory: true), owners: ["claude-code"], level: .user)
        let opencodeRoot = SkillRoot(path: home.appendingPathComponent(".config/opencode/skill", isDirectory: true), owners: ["opencode"], level: .user)
        let builder = CatalogBuilder()
        let skills = builder.build(agents: [
            agent("claude-code", roots: [claudeRoot]),
            agent("opencode", roots: [opencodeRoot]),
        ])
        #expect(skills.count == 2)
        for skill in skills {
            guard case let .multiAgent(ids) = skill.scope else {
                Issue.record("expected multiAgent, got \(skill.scope)")
                return
            }
            #expect(Set(ids) == ["claude-code", "opencode"])
        }
        // 互链：两条记录目录不同但 scope 相同
        #expect(skills[0].directory != skills[1].directory)
    }

    @Test func sameNameDifferentContentIsNotMultiAgent() {
        let home = makeFakeHome(
            files: [
                ".claude/skills/drift/SKILL.md",
                ".config/opencode/skill/drift/SKILL.md",
            ],
            fileContents: [
                ".claude/skills/drift/SKILL.md": "---\nname: drift\ndescription: 分叉 A\n---\nA",
                ".config/opencode/skill/drift/SKILL.md": "---\nname: drift\ndescription: 分叉 B\n---\nB",
            ]
        )
        defer { cleanup(home) }
        let claudeRoot = SkillRoot(path: home.appendingPathComponent(".claude/skills", isDirectory: true), owners: ["claude-code"], level: .user)
        let opencodeRoot = SkillRoot(path: home.appendingPathComponent(".config/opencode/skill", isDirectory: true), owners: ["opencode"], level: .user)
        let builder = CatalogBuilder()
        let skills = builder.build(agents: [
            agent("claude-code", roots: [claudeRoot]),
            agent("opencode", roots: [opencodeRoot]),
        ])
        #expect(skills.count == 2)
        #expect(skills.allSatisfy { skill in
            if case .multiAgent = skill.scope { return false }
            return true
        })
    }
}

@Suite struct CatalogBuilderHealthTests {
    private func agent(_ id: AgentID, roots: [SkillRoot]) -> Agent {
        Agent(id: id, name: id, installState: .installed(configDirectory: nil), skillRoots: roots)
    }

    @Test func buildCarriesHealthFacts() {
        let home = makeFakeHome(
            files: [".claude/skills/demo/SKILL.md"],
            fileContents: [".claude/skills/demo/SKILL.md": "---\nname: demo\n---\nbody"]
        )
        defer { cleanup(home) }
        let root = SkillRoot(
            path: home.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("claude-code", roots: [root])])
        let demo = skills.first { $0.name == "demo" }
        #expect(demo != nil)
        // 有 name 缺 description → 恰好一条 missingDescription
        #expect(demo?.issues.map(\.kind) == [.missingDescription])
        let mdBytes = "---\nname: demo\n---\nbody".utf8.count
        #expect(demo?.skillMdBytes == mdBytes)
        #expect(demo!.totalBytes >= mdBytes)
    }
}
