import Foundation
import Testing
import DomainKit
@testable import InfraKit

/// 生效关系：catalog 层同名遮蔽标注（spec 2026-11-09，官方优先级硬编码）。
@Suite struct ShadowRelationTests {
    private func agent(_ id: AgentID, roots: [SkillRoot]) -> Agent {
        Agent(id: id, name: id, installState: .installed(configDirectory: nil), skillRoots: roots)
    }

    /// 同 agent（claude-code）同名：项目级生效，用户级被遮蔽，方向正确。
    @Test func userCopyShadowedByProjectCopy() throws {
        let home = makeFakeHome(
            files: [
                ".claude/skills/demo/SKILL.md",
                "projects/atlas/.claude/skills/demo/SKILL.md",
            ],
            fileContents: [
                ".claude/skills/demo/SKILL.md": "---\nname: demo\ndescription: user\n---\nU",
                "projects/atlas/.claude/skills/demo/SKILL.md": "---\nname: demo\ndescription: proj\n---\nP",
            ]
        )
        defer { cleanup(home) }
        let projectRoot = ProjectRoot(path: home.appendingPathComponent("projects/atlas", isDirectory: true))
        let projectRootSkill = SkillRoot(
            path: projectRoot.path.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .project(projectRoot)
        )
        let userRoot = SkillRoot(
            path: home.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("claude-code", roots: [userRoot, projectRootSkill])])
        #expect(skills.count == 2)
        let project = try #require(skills.first { $0.skillDescription == "proj" })
        let user = try #require(skills.first { $0.skillDescription == "user" })
        #expect(user.shadowedBy == project.id)
        #expect(user.shadowedCount == 0)
        #expect(project.shadowedBy == nil)
        #expect(project.shadowedCount == 1)
    }

    /// 仅有用户级副本 → 无标注（零噪音）。
    @Test func singleUserCopyUnmarked() {
        let home = makeFakeHome(
            files: [".claude/skills/demo/SKILL.md"],
            fileContents: [".claude/skills/demo/SKILL.md": "---\nname: demo\ndescription: d\n---\nC"]
        )
        defer { cleanup(home) }
        let root = SkillRoot(
            path: home.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("claude-code", roots: [root])])
        #expect(skills.count == 1)
        #expect(skills[0].shadowedBy == nil)
        #expect(skills[0].shadowedCount == 0)
    }

    /// 同名但两个项目副本（同优先级）→ 中性不猜排序。
    @Test func twoProjectCopiesStayNeutral() {
        let home = makeFakeHome(
            files: [
                "projects/atlas/.claude/skills/demo/SKILL.md",
                "projects/borealis/.claude/skills/demo/SKILL.md",
            ],
            fileContents: [
                "projects/atlas/.claude/skills/demo/SKILL.md": "---\nname: demo\ndescription: atlas\n---\nA",
                "projects/borealis/.claude/skills/demo/SKILL.md": "---\nname: demo\ndescription: borealis\n---\nB",
            ]
        )
        defer { cleanup(home) }
        let roots = ["atlas", "borealis"].map { name -> SkillRoot in
            let root = ProjectRoot(path: home.appendingPathComponent("projects/\(name)", isDirectory: true))
            return SkillRoot(
                path: root.path.appendingPathComponent(".claude/skills", isDirectory: true),
                owners: ["claude-code"],
                level: .project(root)
            )
        }
        let skills = CatalogBuilder().build(agents: [agent("claude-code", roots: roots)])
        #expect(skills.count == 2)
        #expect(skills.allSatisfy { $0.shadowedBy == nil && $0.shadowedCount == 0 })
    }

    /// 同名但 agent 无优先级规则（opencode）→ 中性。
    @Test func agentWithoutPolicyStaysNeutral() {
        let home = makeFakeHome(
            files: [
                ".config/opencode/skill/demo/SKILL.md",
                "projects/atlas/.opencode/skill/demo/SKILL.md",
            ],
            fileContents: [
                ".config/opencode/skill/demo/SKILL.md": "---\nname: demo\ndescription: user\n---\nU",
                "projects/atlas/.opencode/skill/demo/SKILL.md": "---\nname: demo\ndescription: proj\n---\nP",
            ]
        )
        defer { cleanup(home) }
        let projectRoot = ProjectRoot(path: home.appendingPathComponent("projects/atlas", isDirectory: true))
        let projectSkillRoot = SkillRoot(
            path: projectRoot.path.appendingPathComponent(".opencode/skill", isDirectory: true),
            owners: ["opencode"],
            level: .project(projectRoot)
        )
        let userRoot = SkillRoot(
            path: home.appendingPathComponent(".config/opencode/skill", isDirectory: true),
            owners: ["opencode"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("opencode", roots: [userRoot, projectSkillRoot])])
        #expect(skills.count == 2)
        #expect(skills.allSatisfy { $0.shadowedBy == nil && $0.shadowedCount == 0 })
    }

    /// 同 agent 同文件名但 frontmatter name 不同（不同名）→ 不标注。
    @Test func differentNamesNotRelated() {
        let home = makeFakeHome(
            files: [
                ".claude/skills/aaa/SKILL.md",
                "projects/atlas/.claude/skills/bbb/SKILL.md",
            ],
            fileContents: [
                ".claude/skills/aaa/SKILL.md": "---\nname: alpha\ndescription: u\n---\nU",
                "projects/atlas/.claude/skills/bbb/SKILL.md": "---\nname: beta\ndescription: p\n---\nP",
            ]
        )
        defer { cleanup(home) }
        let projectRoot = ProjectRoot(path: home.appendingPathComponent("projects/atlas", isDirectory: true))
        let projectSkillRoot = SkillRoot(
            path: projectRoot.path.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .project(projectRoot)
        )
        let userRoot = SkillRoot(
            path: home.appendingPathComponent(".claude/skills", isDirectory: true),
            owners: ["claude-code"],
            level: .user
        )
        let skills = CatalogBuilder().build(agents: [agent("claude-code", roots: [userRoot, projectSkillRoot])])
        #expect(skills.count == 2)
        #expect(skills.allSatisfy { $0.shadowedBy == nil && $0.shadowedCount == 0 })
    }

    /// global/multiAgent scope 不参与遮蔽分组。
    @Test func sharedScopesExcluded() {
        // claude-code + opencode 同名+同 sha → multiAgent；不应生成 shadow 标注
        let home = makeFakeHome(
            files: [
                ".claude/skills/glow/SKILL.md",
                ".config/opencode/skill/glow/SKILL.md",
            ],
            fileContents: [
                ".claude/skills/glow/SKILL.md": "---\nname: glow\ndescription: g\n---\nC",
                ".config/opencode/skill/glow/SKILL.md": "---\nname: glow\ndescription: g\n---\nC",
            ]
        )
        defer { cleanup(home) }
        let claudeRoot = SkillRoot(path: home.appendingPathComponent(".claude/skills", isDirectory: true), owners: ["claude-code"], level: .user)
        let opencodeRoot = SkillRoot(path: home.appendingPathComponent(".config/opencode/skill", isDirectory: true), owners: ["opencode"], level: .user)
        let skills = CatalogBuilder().build(agents: [
            agent("claude-code", roots: [claudeRoot]),
            agent("opencode", roots: [opencodeRoot]),
        ])
        #expect(skills.allSatisfy { $0.shadowedBy == nil && $0.shadowedCount == 0 })
    }
}
