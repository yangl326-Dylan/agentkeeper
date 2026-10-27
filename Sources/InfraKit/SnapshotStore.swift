import Foundation
import DomainKit

/// 快照元数据（manifest 条目）。
public struct SnapshotMetadata: Codable, Hashable, Sendable {
    /// 快照内容指纹（= skill 当时的工作目录指纹）。
    public var sha: String
    public var capturedAt: Date
}

/// Skill 快照引擎（设计 D4）：
/// 目录形态存储于 `~/.agentkeeper/snapshots/<skillKey>/<sha>/`；同指纹去重；
/// 每 skill 保留上限默认 50 份，超出淘汰最旧。磁盘可直接逃生抢救。
public struct SnapshotStore: @unchecked Sendable {
    /// 可配置保留上限（默认 50）。
    private let retentionLimit: Int
    private let baseDirectory: URL
    private let fileManager: FileManager

    public init(baseDirectory: URL, retentionLimit: Int = 50) {
        self.baseDirectory = baseDirectory
        self.retentionLimit = max(1, retentionLimit)
        self.fileManager = .default
    }

    // MARK: - 记录

    /// 指纹变化则落一份目录形态快照；同指纹去重返回 nil。
    @discardableResult
    public func record(skillID: String, directory: URL) throws -> SnapshotMetadata? {
        guard fileManager.fileExists(atPath: directory.path) else {
            throw SkillLifecycleError.sourceMissing(path: directory.path)
        }
        let sha = Fingerprint.sha256OfDirectory(directory) ?? ""
        guard !sha.isEmpty else {
            throw SkillLifecycleError.underlying(path: directory.path, note: "空目录无法快照")
        }

        let skillKeyRoot = skillRoot(skillID: skillID)
        let existing = try loadManifests(skillRoot: skillKeyRoot)
        if existing.contains(where: { $0.sha == sha }) {
            return nil
        }

        let destination = skillKeyRoot.appendingPathComponent(sha, isDirectory: true)
        try fileManager.createDirectory(at: skillKeyRoot, withIntermediateDirectories: true)
        try fileManager.copyItem(at: directory, to: destination)

        var entries = existing
        let metadata = SnapshotMetadata(sha: sha, capturedAt: Date())
        entries.append(metadata)
        entries.sort { $0.capturedAt < $1.capturedAt }

        // 淘汰最旧（含磁盘目录）
        while entries.count > retentionLimit {
            let evicted = entries.removeFirst()
            try? fileManager.removeItem(at: skillKeyRoot.appendingPathComponent(evicted.sha, isDirectory: true))
        }
        try persistManifests(entries, skillRoot: skillKeyRoot)
        return metadata
    }

    // MARK: - 查询

    /// 快照列表（最新的在前）。
    public func snapshots(skillID: String) -> [SnapshotMetadata] {
        guard let entries = try? loadManifests(skillRoot: skillRoot(skillID: skillID)) else {
            return []
        }
        return entries.sorted { $0.capturedAt > $1.capturedAt }
    }

    /// 快照时间线上的实际目录（恢复流程用）。
    public func snapshotURL(skillID: String, sha: String) -> URL {
        skillRoot(skillID: skillID).appendingPathComponent(sha, isDirectory: true)
    }

    // MARK: - 恢复（接入 AtomicMover，设计 D4）

    /// 恢复旧版本：先快照当前（数据不丢）→ 当前目录搬至备份位 → 快照内容复制回原位 →
    /// 指纹校验；失败沿备份回滚（绝不丢当前内容）。
    public func restore(skillID: String, sha: String, currentDirectory: URL) throws {
        guard fileManager.fileExists(atPath: snapshotURL(skillID: skillID, sha: sha).path) else {
            throw SkillLifecycleError.sourceMissing(path: snapshotURL(skillID: skillID, sha: sha).path)
        }
        guard fileManager.fileExists(atPath: currentDirectory.path) else {
            throw SkillLifecycleError.sourceMissing(path: currentDirectory.path)
        }

        // 1. 先快照当前（幂等去重：内容已存在历史时返回 nil，无害）
        _ = try record(skillID: skillID, directory: currentDirectory)

        // 2. 当前目录搬离原位（作为失败回滚依据）
        let mover = AtomicMover()
        let backup = currentDirectory.deletingLastPathComponent()
            .appendingPathComponent(".keeper-backup-\(UUID().uuidString)", isDirectory: true)
        let plan = try mover.planMove(source: currentDirectory, destination: backup)
        do {
            try mover.execute(plan)
        } catch {
            throw SkillLifecycleError.underlying(path: currentDirectory.path, note: "备份当前目录失败: \(error)")
        }

        // 3. 快照内容复制回原位
        do {
            try fileManager.copyItem(at: snapshotURL(skillID: skillID, sha: sha), to: currentDirectory)
        } catch {
            // 复制失败：回滚备份，当前内容无损
            try? mover.rollback(plan)
            throw SkillLifecycleError.underlying(
                path: currentDirectory.path,
                note: "重建旧版本失败: \(error)（当前内容已恢复）"
            )
        }

        // 4. 校验字节级一致
        let restoredSha = Fingerprint.sha256OfDirectory(currentDirectory) ?? ""
        guard restoredSha == sha else {
            try? fileManager.removeItem(at: currentDirectory)
            try? mover.rollback(plan)
            throw SkillLifecycleError.underlying(
                path: currentDirectory.path,
                note: "重建校验失败（出现 \(restoredSha.prefix(8))，期望 \(sha.prefix(8))）——已回滚"
            )
        }
        // 5. 清理备份
        try fileManager.removeItem(at: backup)
    }

    // MARK: - 内部

    /// skillID → 文件系统安全键（对 id 内容取 sha，防路径注入）。
    func skillRoot(skillID: String) -> URL {
        let key = SkillParsing.directoryKey(for: skillID)
        return baseDirectory
            .appendingPathComponent("snapshots", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
    }

    private func loadManifests(skillRoot: URL) throws -> [SnapshotMetadata] {
        let url = skillRoot.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let entries = try? decoder.decode([SnapshotMetadata].self, from: data) {
            return entries
        }
        return []
    }

    private func persistManifests(_ entries: [SnapshotMetadata], skillRoot: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(entries).write(
            to: skillRoot.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }
}
