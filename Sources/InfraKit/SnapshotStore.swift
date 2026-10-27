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
