import Foundation
import DomainKit
import InfraKit

/// 快照编排（5.5）：指纹变化自动快照、历史查询/落账、恢复 action（恢复前先快照当前，保证零丢失）。
/// 恢复完成即触发重扫（rescan 闭包由装配层提供）。
@MainActor
public final class SnapshotService {
    private let snapshots: SnapshotStore
    private let history: OperationHistory
    private let rescan: @Sendable () async -> Void

    public init(
        snapshots: SnapshotStore,
        history: OperationHistory,
        rescan: @escaping @Sendable () async -> Void
    ) {
        self.snapshots = snapshots
        self.history = history
        self.rescan = rescan
    }

    /// 指纹变化才落快照；重复同指纹是幂等 no-op。
    public func autoSnapshot(skill: Skill, directory: URL) async throws {
        let metadata = try snapshots.record(skillID: skill.id, directory: directory)
        if metadata == nil {
            // 同指纹已有快照：不重复记录历史
            return
        }
    }

    /// 恢复 action：回滚到指定快照 → 历史落账（成功/失败明细）→ 触发重扫。
    public func restore(skill: Skill, sha: String) async {
        do {
            try await Task.detached(priority: .userInitiated) { [snapshots, directory = skill.directory] in
                try snapshots.restore(skillID: skill.id, sha: sha, currentDirectory: directory)
            }.value
            history.append(
                skillID: skill.id,
                name: skill.name,
                direction: .snapshotRestore,
                result: .success
            )
        } catch {
            let message = "\(error)"
            history.append(
                skillID: skill.id,
                name: skill.name,
                direction: .snapshotRestore,
                result: .failure(message: message)
            )
        }
        await rescan()
    }

    /// 历史查询（快照时间线上的操作记录）。
    public func historyFor(skillID: String, name: String, limit: Int = 20) -> [OperationRecord] {
        history.recent(limit: limit).filter { $0.skillID == skillID || $0.name == name }
    }
}
