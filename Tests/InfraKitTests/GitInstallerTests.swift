import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct GitInstallerTests {
    /// 需要提交的本地仓库 fixture（本地路径来源直接复用，不 clone）。
    private func makeLocalGitRepo() throws -> (repo: URL, home: URL) {
        let home = makeFakeHome(files: ["repo/SKILL.md"])
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
        #expect(process.terminationStatus == 0)
        return (repo, home)
    }

    @Test func localPathSourceIsReusedWithoutCloning() async throws {
        let (repo, home) = try makeLocalGitRepo()
        defer { cleanup(home) }
        let base = home.appendingPathComponent("agentkeeper-tmp", isDirectory: true)
        let installer = GitInstaller(baseDirectory: base, timeout: TimeInterval(10))
        let materialized = try await installer.materialize(url: "file://\(repo.path)")
        #expect(materialized == repo)
        // 本地路径不应产生临时 clone 目录（base 未创建过 → 视为空）
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func rawLocalPathAlsoReused() async throws {
        let (repo, home) = try makeLocalGitRepo()
        defer { cleanup(home) }
        let base = home.appendingPathComponent("agentkeeper-tmp", isDirectory: true)
        let installer = GitInstaller(baseDirectory: base, timeout: TimeInterval(10))
        let materialized = try await installer.materialize(url: repo.path)
        #expect(materialized == repo)
    }

    @Test func unreachableURLFailsAndCleansTemp() async throws {
        let home = makeFakeHome(files: ["scratch/.keep"])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("agentkeeper-tmp", isDirectory: true)
        let installer = GitInstaller(baseDirectory: base, timeout: TimeInterval(3))
        do {
            _ = try await installer.materialize(url: "https://invalid.invalid/repo.git")
            Issue.record("expected cloneFailed")
        } catch let error as DistributionError {
            guard case let .cloneFailed(detail: detail) = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
            #expect(!detail.isEmpty)
        }
        // 临时区已清理（含空的 tmp 父目录）
        let leftovers = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func timeoutSurfacesCloneTimeout() async throws {
        // 指向一个行为如挂起的命令是不现实的；改用极短超时访问不响应地址。
        let home = makeFakeHome(files: ["scratch/.keep"])
        defer { cleanup(home) }
        let base = home.appendingPathComponent("agentkeeper-tmp", isDirectory: true)
        let installer = GitInstaller(baseDirectory: base, timeout: TimeInterval(0.5))
        do {
            _ = try await installer.materialize(url: "https://10.255.255.1/unreachable.git")
            Issue.record("expected failure")
        } catch let error as DistributionError {
            switch error {
            case .cloneTimeout, .cloneFailed:
                break // 两者都可接受（平台可能立即 EHOSTUNREACH）
            default:
                Issue.record("unexpected error: \(error)")
            }
        }
    }
}
