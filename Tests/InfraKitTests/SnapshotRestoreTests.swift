import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SnapshotRestoreTests {
    private func environment() -> (base: URL, skill: URL, skillsRoot: URL) {
        let home = makeFakeHome(
            files: ["skills/alpha/SKILL.md"],
            fileContents: ["skills/alpha/SKILL.md": "---\nname: alpha\ndescription: d\n---\nV1"]
        )
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let skillsRoot = home.appendingPathComponent("skills", isDirectory: true)
        return (base, home.appendingPathComponent("skills/alpha", isDirectory: true), skillsRoot)
    }

    @Test func restoreOldVersionFirstSnapshotsCurrentThenRebuilds() throws {
        let (base, skill, skillsRoot) = environment()
        defer { cleanup(skillsRoot) }
        let store = SnapshotStore(baseDirectory: base)
        let first = try store.record(skillID: "alpha|claude-code", directory: skill)
        try "V2 全新内容".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        try store.restore(skillID: "alpha|claude-code", sha: first!.sha, currentDirectory: skill)

        // 旧内容字节级重建（指纹一致）
        #expect(Fingerprint.sha256OfDirectory(skill) == first!.sha)
        let content = try String(contentsOf: skill.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(content.contains("V1"))
        // 恢复前先快照了当前（V2 进入历史，不丢数据）
        let shas = Set(store.snapshots(skillID: "alpha|claude-code").map { $0.sha })
        #expect(shas.contains(first!.sha))
    }

    @Test func restoreUnknownSnapshotIsRejected() throws {
        let (base, skill, skillsRoot) = environment()
        defer { cleanup(skillsRoot) }
        let store = SnapshotStore(baseDirectory: base)
        #expect(throws: SkillLifecycleError.self) {
            try store.restore(skillID: "alpha|claude-code", sha: "no-such-sha", currentDirectory: skill)
        }
        // 当前目录未受影响
        #expect(FileManager.default.fileExists(atPath: skill.appendingPathComponent("SKILL.md").path))
    }

    @Test func restoreMissingCurrentDirIsRejected() throws {
        let (base, skill, skillsRoot) = environment()
        defer { cleanup(skillsRoot) }
        let store = SnapshotStore(baseDirectory: base)
        let first = try store.record(skillID: "alpha|claude-code", directory: skill)
        try FileManager.default.removeItem(at: skill)
        #expect(throws: SkillLifecycleError.self) {
            try store.restore(skillID: "alpha|claude-code", sha: first!.sha, currentDirectory: skill)
        }
    }
}
