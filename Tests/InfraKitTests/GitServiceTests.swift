import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct GitServiceTests {
    private func makeGitRepo() throws -> (repo: URL, scratch: URL) {
        let home = makeFakeHome(files: ["repo/.gitkeep"])
        let repo = home.appendingPathComponent("repo", isDirectory: true)
        let commitEnvironment = [
            "GIT_COMMITTER_NAME": "tester",
            "GIT_COMMITTER_EMAIL": "t@t",
            "GIT_AUTHOR_NAME": "tester",
            "GIT_AUTHOR_EMAIL": "t@t",
        ]
        func git(_ args: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = args
            process.currentDirectoryURL = repo
            var environment = commitEnvironment
            environment["HOME"] = home.path
            process.environment = environment
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw GitServiceError.notGitRepository(path: repo.path)
            }
        }
        try git(["init", "-q"])
        try git(["add", "."])
        try git(["commit", "-q", "-m", "第一版"])
        try "v2 content".write(to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."])
        try git(["commit", "-q", "-m", "第二版"])
        return (repo, home)
    }

    @Test func historyParsesPorcelainOutput() throws {
        let (repo, home) = try makeGitRepo()
        defer { cleanup(home) }
        let service = GitService(gitExecutablePath: "/usr/bin/git")
        let history = service.history(directory: repo)
        #expect(history.count == 2)
        #expect(history[0].subject == "第二版")
        #expect(history[1].subject == "第一版")
        #expect(history[0].hash.count >= 8)
    }

    @Test func nonGitDirectoryReturnsEmptyHistoryNoThrow() throws {
        let home = makeFakeHome(files: ["plain/readme.md"])
        defer { cleanup(home) }
        let service = GitService(gitExecutablePath: "/usr/bin/git")
        let history = service.history(directory: home.appendingPathComponent("plain", isDirectory: true))
        #expect(history.isEmpty)
        // diff 同样体面空
        #expect(service.uncommittedDiff(directory: home.appendingPathComponent("plain", isDirectory: true)).isEmpty)
        // 幂等：反复调用结果一致
        #expect(service.history(directory: home.appendingPathComponent("plain", isDirectory: true)) == history)
    }

    @Test func versionSniffingDetectsSystemGit() {
        let service = GitService(gitExecutablePath: "/usr/bin/git")
        let version = service.version()
        #expect(version != nil)
        #expect(version!.lowercased().contains("git"))
    }

    @Test func cleanRepoDiffIsEmptyDirtyRepoDiffHasContent() throws {
        let (repo, home) = try makeGitRepo()
        defer { cleanup(home) }
        let service = GitService(gitExecutablePath: "/usr/bin/git")
        #expect(service.uncommittedDiff(directory: repo).isEmpty)

        try "uncommitted change".write(to: repo.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        let dirty = service.uncommittedDiff(directory: repo)
        #expect(dirty.contains("uncommitted change"))
    }
}
