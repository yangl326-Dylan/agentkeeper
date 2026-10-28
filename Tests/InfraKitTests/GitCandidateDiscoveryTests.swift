import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct GitCandidateDiscoveryTests {
    private let installer = GitInstaller(
        baseDirectory: URL(fileURLWithPath: "/nonexistent-base"),
        gitExecutablePath: "/usr/bin/git"
    )

    /// 仓库根本身是合法 skill → 单候选（名字取仓库目录名）。
    @Test func singleSkillRepoRootCandidate() throws {
        let home = makeFakeHome(files: ["repo/SKILL.md"])
        defer { cleanup(home) }
        let repo = home.appendingPathComponent("repo", isDirectory: true)
        try "---\nname: docs-writer\ndescription: 写作\n---\n内容\n".write(
            to: repo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let candidates = installer.candidates(for: "some-url", in: repo)
        #expect(candidates.count == 1)
        #expect(candidates[0].directory == repo)
        #expect(candidates[0].name == "repo")
        #expect(!candidates[0].sha256.isEmpty)
    }

    /// 仓库根非法但一级子目录是合法 skill → 多候选。
    @Test func multiSkillSubdirectoriesDiscovered() throws {
        let home = makeFakeHome(files: [
            "repo/alpha/SKILL.md",
            "repo/beta/SKILL.md",
            "repo/notes.txt", // 非目录忽略
        ])
        defer { cleanup(home) }
        let repo = home.appendingPathComponent("repo", isDirectory: true)
        for name in ["alpha", "beta"] {
            try "---\nname: \(name)\ndescription: \(name) 说明\n---\n内容\n".write(
                to: repo.appendingPathComponent(name, isDirectory: true).appendingPathComponent("SKILL.md"),
                atomically: true, encoding: .utf8
            )
        }
        let candidates = installer.candidates(for: "some-url", in: repo)
        #expect(candidates.count == 2)
        #expect(Set(candidates.map(\.name)) == ["alpha", "beta"])
    }

    /// 根合法时不再叠加子目录候选。
    @Test func rootValidSuppressesSubdirectoryScan() throws {
        let home = makeFakeHome(files: ["repo/SKILL.md", "repo/child/SKILL.md"])
        defer { cleanup(home) }
        let repo = home.appendingPathComponent("repo", isDirectory: true)
        try "---\nname: root-skill\ndescription: 根\n---\n内容\n".write(
            to: repo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        try "---\nname: child-skill\ndescription: 子\n---\n内容\n".write(
            to: repo.appendingPathComponent("child", isDirectory: true).appendingPathComponent("SKILL.md"),
            atomically: true, encoding: .utf8
        )
        let candidates = installer.candidates(for: "some-url", in: repo)
        #expect(candidates.count == 1)
        #expect(candidates[0].name == "repo")
    }

    /// 空/非法仓库 → 零候选（不报错，由上层决定 invalidSource）。
    @Test func emptyRepoYieldsNoCandidates() throws {
        let home = makeFakeHome(files: ["repo/readme.md"])
        defer { cleanup(home) }
        let repo = home.appendingPathComponent("repo", isDirectory: true)
        #expect(installer.candidates(for: "some-url", in: repo).isEmpty)
    }

    /// 候选名来源仓库 URL 时随传入值记录（供历史审计）。
    @Test func repositoryURLCarried() throws {
        let home = makeFakeHome(files: ["repo/SKILL.md"])
        defer { cleanup(home) }
        let repo = home.appendingPathComponent("repo", isDirectory: true)
        try "---\nname: n\ndescription: d\n---\n内容\n".write(
            to: repo.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let candidates = installer.candidates(for: "https://example.com/x/repo.git", in: repo)
        #expect(candidates[0].repositoryURL == "https://example.com/x/repo.git")
    }
}
