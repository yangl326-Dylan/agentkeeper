import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SkillDistributorRollbackTests {
    @Test func injectedCopyFailureLeavesNoTargetOrStaging() async throws {
        let home = makeFakeHome(files: ["src/SKILL.md", "dest/.keep"])
        defer { cleanup(home) }
        let source = home.appendingPathComponent("src", isDirectory: true)
        try "---\nname: src\ndescription: 注入失败\n---\n正文\n".write(
            to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let targetRoot = home.appendingPathComponent("dest/skills", isDirectory: true)
        try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)

        let failingCopier: @Sendable (URL, URL) throws -> Void = { (source: URL, staging: URL) in
            // 模拟拷到一半断电：先写出部分内容再炸
            try FileManager.default.createDirectory(
                at: staging.appendingPathComponent("SKILL.md"), withIntermediateDirectories: true
            )
            try "partial".write(to: staging.appendingPathComponent("SKILL.md/partial.txt"), atomically: true, encoding: .utf8)
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: source.path])
        }
        let distributor = SkillDistributor(
            git: GitInstaller(baseDirectory: home.appendingPathComponent("ak")),
            copier: failingCopier
        )
        do {
            _ = try await distributor.install(
                source: .localDirectory(path: source.path), targetSkillRoot: targetRoot
            )
            Issue.record("expected ioFailure")
        } catch let error as DistributionError {
            guard case .ioFailure = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }
        // 目标不存在、无 stage 半成品残留
        let entries = try FileManager.default.contentsOfDirectory(at: targetRoot, includingPropertiesForKeys: nil)
        #expect(entries.filter { $0.lastPathComponent != ".keep" }.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: targetRoot.appendingPathComponent("src").path))
    }
}
