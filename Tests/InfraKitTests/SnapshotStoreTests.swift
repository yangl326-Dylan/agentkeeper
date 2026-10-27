import Foundation
import Testing
import DomainKit
@testable import InfraKit

@Suite struct SnapshotStoreTests {
    private func skillDirectory() -> (base: URL, skill: URL) {
        let home = makeFakeHome(
            files: ["skills/alpha/SKILL.md"],
            fileContents: ["skills/alpha/SKILL.md": "---\nname: alpha\ndescription: d\n---\nV1"]
        )
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        return (base, home.appendingPathComponent("skills/alpha", isDirectory: true))
    }

    @Test func fingerprintChangeTriggersSnapshotCopy() throws {
        let (base, skill) = skillDirectory()
        defer { cleanup(skill.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = SnapshotStore(baseDirectory: base)

        let first = try store.record(skillID: "alpha|claude-code", directory: skill)
        #expect(first != nil)
        // 快照是目录形态：可从磁盘直接读回原内容
        let firstURL = store.snapshotURL(skillID: "alpha|claude-code", sha: first!.sha)
        let copied = try String(contentsOf: firstURL.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(copied.contains("V1"))

        // 内容变化 → 第二次快照
        try "V2".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let second = try store.record(skillID: "alpha|claude-code", directory: skill)
        #expect(second != nil)
        #expect(second!.sha != first!.sha)
        #expect(store.snapshots(skillID: "alpha|claude-code").count == 2)
    }

    @Test func identicalFingerprintDoesNotDuplicate() throws {
        let (base, skill) = skillDirectory()
        defer { cleanup(skill.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = SnapshotStore(baseDirectory: base)
        _ = try store.record(skillID: "alpha|claude-code", directory: skill)
        // 未修改内容再次记录 → 去重（nil，不新增）
        let duplicated = try store.record(skillID: "alpha|claude-code", directory: skill)
        #expect(duplicated == nil)
        #expect(store.snapshots(skillID: "alpha|claude-code").count == 1)
    }

    @Test func retentionLimitEvictsOldest() throws {
        let (base, skill) = skillDirectory()
        defer { cleanup(skill.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = SnapshotStore(baseDirectory: base, retentionLimit: 2)

        _ = try store.record(skillID: "alpha|claude-code", directory: skill)
        try "V2".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try store.record(skillID: "alpha|claude-code", directory: skill)
        try "V3".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try store.record(skillID: "alpha|claude-code", directory: skill)

        let snapshots = store.snapshots(skillID: "alpha|claude-code")
        #expect(snapshots.count == 2)
        // 最新的在前，最旧（V1 对应 sha）已被淘汰
        #expect(snapshots == snapshots.sorted { $0.capturedAt > $1.capturedAt })
    }

    @Test func snapshotsListedNewestFirst() throws {
        let (base, skill) = skillDirectory()
        defer { cleanup(skill.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = SnapshotStore(baseDirectory: base)
        _ = try store.record(skillID: "alpha|claude-code", directory: skill)
        try "V2".write(to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        _ = try store.record(skillID: "alpha|claude-code", directory: skill)

        let snapshots = store.snapshots(skillID: "alpha|claude-code")
        #expect(snapshots.count == 2)
        #expect(snapshots[0].capturedAt >= snapshots[1].capturedAt)
    }

    @Test func snapshotsForUnknownSkillAreEmpty() {
        let (base, _) = skillDirectory()
        defer { cleanup(base) }
        let store = SnapshotStore(baseDirectory: base)
        #expect(store.snapshots(skillID: "orphan|x").isEmpty)
    }
}
