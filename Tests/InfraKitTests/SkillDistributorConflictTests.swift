import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SkillDistributorConflictTests {
    @Test func conflictingTargetAbortsWithoutWriting() async throws {
        let home = makeFakeHome(files: [
            "a/.claude/skills/review/SKILL.md",
            "b/.codex/skills/placeholder.txt",
        ])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("a/.claude/skills/review", isDirectory: true)
        try "---\nname: review\ndescription: 新版本\n---\n新版正文\n".write(
            to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        // 目标已有同名但内容不同
        let targetRoot = home.appendingPathComponent("b/.codex/skills", isDirectory: true)
        let conflicting = targetRoot.appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(at: conflicting, withIntermediateDirectories: true)
        try "---\nname: review\ndescription: 旧版本\n---\n旧版正文\n".write(
            to: conflicting.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let existingSha = Fingerprint.sha256OfDirectory(conflicting)
        let incomingSha = Fingerprint.sha256OfDirectory(source)

        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        do {
            _ = try await distributor.install(
                source: .existingSkill(agentID: "claude-code", name: "review", directoryPath: source.path),
                targetSkillRoot: targetRoot
            )
            Issue.record("expected conflict")
        } catch let error as DistributionError {
            guard case let .conflict(detail) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(detail.targetPath == conflicting.path)
            #expect(detail.existingSha256 == existingSha)
            #expect(detail.incomingSha256 == incomingSha)
        }
        // 双方均无改动
        #expect(Fingerprint.sha256OfDirectory(conflicting) == existingSha)
        #expect(Fingerprint.sha256OfDirectory(source) == incomingSha)
        // 无 stage 残留
        let rootContents = try FileManager.default.contentsOfDirectory(at: targetRoot, includingPropertiesForKeys: nil)
        #expect(rootContents.map(\.lastPathComponent).sorted() == ["placeholder.txt", "review"])
    }

    @Test func identicalTargetReportsAlreadyDistributed() async throws {
        let home = makeFakeHome(files: [
            "a/.claude/skills/review/SKILL.md",
            "b/.codex/skills/placeholder.txt",
        ])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("a/.claude/skills/review", isDirectory: true)
        try "---\nname: review\ndescription: 原版\n---\n正文\n".write(
            to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let targetRoot = home.appendingPathComponent("b/.codex/skills", isDirectory: true)
        // 目标 = 来源的完整复制（同名同指纹）
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        _ = try await distributor.install(
            source: .existingSkill(agentID: "claude-code", name: "review", directoryPath: source.path),
            targetSkillRoot: targetRoot
        )
        let sha = Fingerprint.sha256OfDirectory(source)!
        // 再次安装同内容来源（以本地目录形式、同名 review）→ alreadyDistributed，不重复复制
        let copySource = home.appendingPathComponent("other/review", isDirectory: true)
        try FileManager.default.createDirectory(at: copySource, withIntermediateDirectories: true)
        try Data(contentsOf: source.appendingPathComponent("SKILL.md"))
            .write(to: copySource.appendingPathComponent("SKILL.md"), options: .atomic)
        let result = try await distributor.install(
            source: .localDirectory(path: copySource.path),
            targetSkillRoot: targetRoot
        )
        guard case let .alreadyDistributed(target) = result else {
            Issue.record("expected alreadyDistributed, got \(result)")
            return
        }
        #expect(target == targetRoot.appendingPathComponent("review", isDirectory: true))
        // 目录里仍然只有 review + placeholder
        let entries = try FileManager.default.contentsOfDirectory(at: targetRoot, includingPropertiesForKeys: nil)
        #expect(entries.map(\.lastPathComponent).sorted() == ["placeholder.txt", "review"])
        _ = sha
    }
}
