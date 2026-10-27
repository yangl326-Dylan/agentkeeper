import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SkillIndexTests {
    private func sampleSkill(_ name: String, agent: AgentID, scope: SkillScope, sha: String) -> Skill {
        Skill(
            id: "\(name)|\(agent)",
            name: name,
            directory: URL(fileURLWithPath: "/tmp/skills/\(agent)/\(name)"),
            scope: scope,
            status: .enabled,
            sha256: sha,
            frontmatterName: name,
            skillDescription: "desc \(name)",
            fileCount: 3,
            lastModified: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    private func makeIndex() -> (SkillIndex, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-index-\(UUID().uuidString)", isDirectory: true)
        let index = SkillIndex(databaseDirectory: dir)
        return (index, dir)
    }

    @Test func upsertAndReadBackCodableScope() {
        let (index, _) = makeIndex()
        let skills = [
            sampleSkill("alpha", agent: "claude-code", scope: .agentOnly(agentID: "claude-code"), sha: "aaa"),
            sampleSkill("beta", agent: "claude-code", scope: .global(owners: ["claude-code", "opencode"]), sha: "bbb"),
            sampleSkill("proj", agent: "opencode", scope: .project(agentID: "opencode", root: ProjectRoot(path: "/Users/x/code/atlas")), sha: "ccc"),
        ]
        index.upsert(skills)
        let loaded = index.all()
        #expect(loaded.count == 3)
        #expect(loaded.first { $0.id == "beta|claude-code" }?.scope == .global(owners: ["claude-code", "opencode"]))
        #expect(loaded.first { $0.id == "proj|opencode" }?.scope == .project(agentID: "opencode", root: ProjectRoot(path: "/Users/x/code/atlas")))
    }

    @Test func replaceAllDropsStaleRows() {
        let (index, _) = makeIndex()
        index.upsert([sampleSkill("stale", agent: "claude-code", scope: .agentOnly(agentID: "claude-code"), sha: "old")])
        index.replaceAll([
            sampleSkill("fresh", agent: "claude-code", scope: .agentOnly(agentID: "claude-code"), sha: "new"),
        ])
        #expect(index.all().count == 1)
        #expect(index.all()[0].name == "fresh")
    }

    @Test func upsertOverwritesSameID() {
        let (index, _) = makeIndex()
        index.upsert([sampleSkill("alpha", agent: "claude-code", scope: .agentOnly(agentID: "claude-code"), sha: "v1")])
        index.upsert([sampleSkill("alpha", agent: "claude-code", scope: .agentOnly(agentID: "claude-code"), sha: "v2")])
        #expect(index.all().count == 1)
        #expect(index.all()[0].sha256 == "v2")
    }

    @Test func corruptedDatabaseDetectedAndRebuilt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ak-index-\(UUID().uuidString)", isDirectory: true)
        // 先让首个实例完整关闭（checkpoint 写回主文件），再做确定性破坏
        do {
            let index = SkillIndex(databaseDirectory: dir)
            index.upsert([sampleSkill("x", agent: "a", scope: .agentOnly(agentID: "a"), sha: "s")])
        }
        let dbFile = dir.appendingPathComponent("skills.db")
        let handle = try FileHandle(forWritingTo: dbFile)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("THIS IS NOT SQLITE AT ALL!".utf8))
        try handle.close()

        let reopened = SkillIndex(databaseDirectory: dir)
        #expect(reopened.integrity() == false)
        reopened.rebuild()
        #expect(reopened.integrity())
        #expect(reopened.all().isEmpty)
    }
}
