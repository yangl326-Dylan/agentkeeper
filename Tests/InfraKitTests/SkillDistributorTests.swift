import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SkillDistributorInstallTests {
    private func makeSkill(_ home: URL, agentDir: String, name: String, body: String = "正文") throws -> URL {
        let directory = home.appendingPathComponent("\(agentDir)/skills/\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: \(name) 说明\n---\n\(body)\n".write(
            to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        return directory
    }

    @Test func installCopiesToTargetWithoutTouchingSource() async throws {
        let home = makeFakeHome(files: [
            "a/.claude/skills/review/SKILL.md",
            "b/.codex/SKILL_MARKER", // 目标 agent 的 skill 根在此 fixture 里手动建
        ])
        defer { cleanup(home) }
        let source = try makeSkill(home, agentDir: "a/.claude", name: "review")
        let targetRoot = home.appendingPathComponent("b/.codex/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        let result = try await distributor.install(
            source: .existingSkill(agentID: "claude-code", name: "review", directoryPath: source.path),
            targetSkillRoot: targetRoot
        )
        guard case let .installed(name, target, sha256) = result else {
            Issue.record("expected installed, got \(result)")
            return
        }
        #expect(name == "review")
        #expect(target == targetRoot.appendingPathComponent("review", isDirectory: true))
        #expect(sha256 == Fingerprint.sha256OfDirectory(source)!)

        // 目标内容一致
        let copied = String(
            data: try Data(contentsOf: target.appendingPathComponent("SKILL.md")),
            encoding: .utf8
        )
        let original = String(
            data: try Data(contentsOf: source.appendingPathComponent("SKILL.md")),
            encoding: .utf8
        )
        #expect(copied == original)

        // 来源不变
        #expect(Fingerprint.sha256OfDirectory(source) == sha256)
    }

    @Test func installFromNonexistentSourceThrowsInvalidSource() async throws {
        let home = makeFakeHome(files: ["scratch/.keep"])
        defer { cleanup(home) }
        let targetRoot = home.appendingPathComponent("scratch/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        do {
            _ = try await distributor.install(
                source: .existingSkill(agentID: "x", name: "missing", directoryPath: home.appendingPathComponent("nope").path),
                targetSkillRoot: targetRoot
            )
            Issue.record("expected error")
        } catch let error as DistributionError {
            guard case .invalidSource = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }
        // 目标侧无任何写入（skill 根 even 不存在或为空）
        let targetContents = ((try? FileManager.default.contentsOfDirectory(at: targetRoot, includingPropertiesForKeys: nil)) ?? [])
        #expect(targetContents.isEmpty)
    }
}
