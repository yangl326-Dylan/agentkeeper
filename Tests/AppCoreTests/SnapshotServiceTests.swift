import Foundation
import Testing
import DomainKit
import InfraKit
@testable import AppCore

/// 5.5：AppCore 层的快照联动/历史/恢复 action 状态流。
@Suite @MainActor struct SnapshotServiceTests {
    private func skill(_ name: String, id: String, directory: URL, sha: String) -> Skill {
        Skill(id: id, name: name, directory: directory, scope: .agentOnly(agentID: "claude-code"), sha256: sha)
    }

    @Test func fingerprintChangeTriggersSnapshotOncePerSha() async throws {
        let home = makeFakeHome(
            files: ["skills/alpha/SKILL.md"],
            fileContents: ["skills/alpha/SKILL.md": "---\nname: alpha\ndescription: d\n---\nV1"]
        )
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let snapshotStore = SnapshotStore(baseDirectory: base)
        let history = OperationHistory(directory: base)
        let service = SnapshotService(
            snapshots: snapshotStore,
            history: history,
            rescan: {
                // 恢复动作完成后理应重扫（合同：调用计数）
                return
            }
        )
        let directory = home.appendingPathComponent("skills/alpha", isDirectory: true)
        let sample = skill("alpha", id: "alpha|claude-code", directory: directory, sha: "sha-v1")

        // 第一次：落快照
        try await service.autoSnapshot(skill: sample, directory: directory)
        let historyAfterFirst = history.recent(limit: 10)
        #expect(historyAfterFirst.count == 0)
        #expect(snapshotStore.snapshots(skillID: sample.id).count == 1)

        // 相同指纹（未改动）：不再触发
        try await service.autoSnapshot(skill: sample, directory: directory)
        #expect(snapshotStore.snapshots(skillID: sample.id).count == 1)
        let historySecond = history.recent(limit: 10)
        #expect(historySecond.isEmpty)
        _ = historyAfterFirst
        _ = historySecond
    }

    @Test func restoreActionRecordsHistoryAndRescanRuns() async throws {
        let home = makeFakeHome(
            files: ["skills/alpha/SKILL.md"],
            fileContents: ["skills/alpha/SKILL.md": "---\nname: alpha\ndescription: d\n---\nV1"]
        )
        defer { cleanup(home) }
        let base = home.appendingPathComponent("ak-base", isDirectory: true)
        let snapshotStore = SnapshotStore(baseDirectory: base)
        let history = OperationHistory(directory: base)
        let rescanRuns = IntegerBox()
        let service = SnapshotService(
            snapshots: snapshotStore,
            history: history,
            rescan: {
                rescanRuns.increment()
                return
            }
        )
        let directory = home.appendingPathComponent("skills/alpha", isDirectory: true)
        let sample = skill("alpha", id: "alpha|claude-code", directory: directory, sha: "sha")
        _ = try? snapshotStore.record(skillID: sample.id, directory: directory)
        try "---\nname: alpha\ndescription: d\n---\nV2".write(
            to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
        )
        let shaBefore = snapshotStore.snapshots(skillID: sample.id)[0].sha

        // 恢复 action（应用层）：回滚 + 历史落账 + 重扫
        await service.restore(skill: sample, sha: shaBefore)
        #expect(try String(contentsOf: directory.appendingPathComponent("SKILL.md"), encoding: .utf8).contains("V1"))
        let records = history.recent(limit: 10)
        #expect(records.count == 1)
        if let record = records.first {
            #expect(record.name == "alpha")
            #expect(record.direction == .snapshotRestore)
        }
        #expect(rescanRuns.value == 1)
    }
}
