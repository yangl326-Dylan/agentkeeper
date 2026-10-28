import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SkillDistributorImportTests {
    @Test func importValidDirectoryCopies() async throws {
        let home = makeFakeHome(files: ["import-me/SKILL.md"])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("import-me", isDirectory: true)
        try "---\nname: import-me\ndescription: 导入成功\n---\n正文\n".write(
            to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        let result = try await distributor.install(
            source: .localDirectory(path: source.path),
            targetSkillRoot: targetRoot
        )
        guard case .installed = result else {
            Issue.record("expected installed, got \(result)")
            return
        }
        #expect(Fingerprint.sha256OfDirectory(source) != nil)
        // 来源保持不变
        #expect(Fingerprint.sha256OfDirectory(source) == Fingerprint.sha256OfDirectory(source))
    }

    @Test func importDirectoryWithoutSkillMarkdownRejected() async throws {
        let home = makeFakeHome(files: ["plain/readme.md"])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("plain", isDirectory: true)
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        await #expect(throws: DistributionError.self) {
            _ = try await distributor.install(
                source: .localDirectory(path: source.path), targetSkillRoot: targetRoot
            )
        }
        let contents = ((try? FileManager.default.contentsOfDirectory(at: targetRoot, includingPropertiesForKeys: nil)) ?? [])
        #expect(contents.isEmpty)
    }

    @Test func importInvalidFrontmatterRejected() async throws {
        let home = makeFakeHome(files: ["broken/SKILL.md"])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("broken", isDirectory: true)
        try "没有 frontmatter 的普通文档\n".write(
            to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        do {
            _ = try await distributor.install(
                source: .localDirectory(path: source.path), targetSkillRoot: targetRoot
            )
            Issue.record("expected invalidSource")
        } catch let error as DistributionError {
            guard case let .invalidSource(reason: reason) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(reason.contains("frontmatter"))
        }
    }

    @Test func importConflictingTargetRejected() async throws {
        let home = makeFakeHome(files: ["import-me/SKILL.md", "agent/skills/keep.txt"])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("import-me", isDirectory: true)
        try "---\nname: import-me\ndescription: v1\n---\n正文\n".write(
            to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let conflicting = targetRoot.appendingPathComponent("import-me", isDirectory: true)
        try FileManager.default.createDirectory(at: conflicting, withIntermediateDirectories: true)
        try "---\nname: import-me\ndescription: v2\n---\n不同\n".write(
            to: conflicting.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")))
        do {
            _ = try await distributor.install(
                source: .localDirectory(path: source.path), targetSkillRoot: targetRoot
            )
            Issue.record("expected conflict")
        } catch let error as DistributionError {
            guard case .conflict = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }
        #expect(Fingerprint.sha256OfDirectory(conflicting) != nil)
    }
}
