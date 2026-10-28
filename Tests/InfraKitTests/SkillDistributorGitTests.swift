import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SkillDistributorGitTests {
    @discardableResult
    private func makeGitRepo(with files: [String]) throws -> (repo: URL, home: URL) {
        let home = makeFakeHome(files: files)
        let repo = home.appendingPathComponent("repo", isDirectory: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["init", "-q"]
        process.currentDirectoryURL = repo
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = home.path
        environment["GIT_AUTHOR_NAME"] = "tester"
        environment["GIT_AUTHOR_EMAIL"] = "t@t"
        environment["GIT_COMMITTER_NAME"] = "tester"
        environment["GIT_COMMITTER_EMAIL"] = "t@t"
        process.environment = environment
        try process.run()
        process.waitUntilExit()
        return (repo, home)
    }

    @Test func gitSingleSkillRepoInstallsAndCleansTemp() async throws {
        let (repo, home) = try makeGitRepo(with: ["repo/SKILL.md"])
        defer { cleanup(home) }
        try "---\nname: repo\ndescription: 仓库根技能\n---\n正文\n".write(
            to: repo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let base = home.appendingPathComponent("ak", isDirectory: true)
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: base, timeout: TimeInterval(20)))
        let result = try await distributor.install(
            source: .gitRepository(url: repo.path),
            targetSkillRoot: targetRoot
        )
        guard case let .installed(name, target, _) = result else {
            Issue.record("expected installed, got \(result)")
            return
        }
        #expect(name == "repo")
        #expect(target == targetRoot.appendingPathComponent("repo", isDirectory: true))
        // 本地路径来源：临时区不产生目录
        let contents = ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
        #expect(contents.isEmpty)
    }

    @Test func gitFileURLCloneWorksWithTempCleanup() async throws {
        let (repo, home) = try makeGitRepo(with: ["repo/SKILL.md"])
        defer { cleanup(home) }
        try "---\nname: repo\ndescription: 仓库根技能\n---\n正文\n".write(
            to: repo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let base = home.appendingPathComponent("ak", isDirectory: true)
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: base, timeout: TimeInterval(20)))
        let result = try await distributor.install(
            source: .gitRepository(url: "file://\(repo.path)"),
            targetSkillRoot: targetRoot
        )
        guard case .installed = result else {
            Issue.record("expected installed, got \(result)")
            return
        }
        // clone 完成：临时区彻底干净
        let contents = ((try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [])
        #expect(contents.isEmpty)
    }

    @Test func gitMultiCandidateRepoDirectsToSelection() async throws {
        let (repo, home) = try makeGitRepo(with: ["repo/alpha/SKILL.md", "repo/beta/SKILL.md"])
        defer { cleanup(home) }
        for name in ["alpha", "beta"] {
            try "---\nname: \(name)\ndescription: \(name)\n---\n正文\n".write(
                to: repo.appendingPathComponent(name, isDirectory: true).appendingPathComponent("SKILL.md"),
                atomically: true, encoding: .utf8
            )
        }
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak"), timeout: TimeInterval(20)))
        do {
            _ = try await distributor.install(
                source: .gitRepository(url: repo.path), targetSkillRoot: targetRoot
            )
            Issue.record("expected invalidSource（引导候选面板）")
        } catch let error as DistributionError {
            guard case let .invalidSource(reason: reason) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(reason.contains("候选"))
        }
        // 未勾选前不产生任何写入
        let entries = ((try? FileManager.default.contentsOfDirectory(at: targetRoot, includingPropertiesForKeys: nil)) ?? [])
        #expect(entries.isEmpty)
    }

    @Test func gitRepoWithoutSkillsReportsInvalidSource() async throws {
        let (repo, home) = try makeGitRepo(with: ["repo/readme.md"])
        defer { cleanup(home) }
        let targetRoot = home.appendingPathComponent("agent/skills", isDirectory: true)
        let distributor = SkillDistributor(git: GitInstaller(baseDirectory: home.appendingPathComponent("ak"), timeout: TimeInterval(20)))
        do {
            _ = try await distributor.install(
                source: .gitRepository(url: repo.path), targetSkillRoot: targetRoot
            )
            Issue.record("expected invalidSource")
        } catch let error as DistributionError {
            guard case .invalidSource = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }
    }
}
