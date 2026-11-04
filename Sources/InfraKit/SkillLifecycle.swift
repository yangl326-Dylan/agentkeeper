import Foundation
import DomainKit

/// 生命周期错误（UI 冲突面板按 case 展示明细）。
public enum SkillLifecycleError: Error, Hashable {
    case sourceMissing(path: String)
    case destinationOccupied(path: String)
    case destinationParentMissing(path: String)
    case manifestMissing(path: String)
    case manifestCorrupted(path: String)
    case underlying(path: String, note: String)
}

/// 禁用 manifest：恢复的全部依据（4.3）。
public struct DisabledSkillRecord: Codable, Hashable, Sendable {
    /// 恢复目标：agent 的原 skill 目录全路径。
    public var originalPath: String
    public var agentID: AgentID
    public var name: String
    public var sha256: String
    public var disabledAt: Date

    public init(originalPath: String, agentID: AgentID, name: String, sha256: String, disabledAt: Date = Date()) {
        self.originalPath = originalPath
        self.agentID = agentID
        self.name = name
        self.sha256 = sha256
        self.disabledAt = disabledAt
    }
}

/// Skill 生命周期（MVP：禁用/恢复）。
/// 设计 D3：统一禁用区 `~/.agentkeeper/disabled/<agent>/<skill>/`；
/// manifest JSON 与禁用目录同放（`<skill>.manifest.json`）。
public struct SkillLifecycle: @unchecked Sendable {
    /// 统一禁用区根（默认 ~/.agentkeeper；测试注入）。
    private let baseDirectory: URL
    /// 巡检时的 agent 名单（仅作兜底并集；条目枚举以磁盘目录为准，自定义 agent 自动可见）。
    private let knownAgentIDs: [String]
    private let mover: AtomicMover
    private let fileManager: FileManager

    public init(baseDirectory: URL, knownAgentIDs: [String] = [], mover: AtomicMover = AtomicMover()) {
        self.baseDirectory = baseDirectory
        self.knownAgentIDs = knownAgentIDs
        self.mover = mover
        self.fileManager = .default
    }

    /// 禁用：原子搬移至禁用区 + manifest 写盘。冲突/占用一律中止，绝不覆盖。
    /// （实现收敛于区通用搬移——与回收站同构，manifest 惯例一致。）
    @discardableResult
    public func disable(agentID: AgentID, skillDirectory: URL) throws -> DisabledSkillRecord {
        try moveToZone(.disabled, agentID: agentID, skillDirectory: skillDirectory)
    }

    // MARK: - 恢复（4.3）

    /// 恢复：按 manifest 回原路径。原路径被占 → 中止并输出冲突明细，绝不覆盖。
    /// 成功后清理 manifest 与（已空的）禁用目录。
    /// （实现收敛于区通用恢复——与回收站同构。）
    @discardableResult
    public func enable(agentID: AgentID, name: String) throws -> DisabledSkillRecord {
        try restoreFromZone(.disabled, agentID: agentID, name: name)
    }

    // MARK: - 列举（停用区 / 回收站）

    /// 区条目：manifest 记录 + 磁盘定位（UI 列表与 CLI 展示共用）。
    public struct ZoneEntry: Hashable, Sendable {
        public var record: DisabledSkillRecord
        public var directoryPath: String
        public var manifestPath: String

        public init(record: DisabledSkillRecord, directoryPath: String, manifestPath: String) {
            self.record = record
            self.directoryPath = directoryPath
            self.manifestPath = manifestPath
        }
    }

    /// 停用区全表（<base>/disabled/<agent>/*.manifest.json）。
    public func disabledEntries() throws -> [ZoneEntry] {
        try entries(zone: .disabled)
    }

    /// 回收站全表（<base>/trash/<agent>/*.manifest.json）。
    public func trashEntries() throws -> [ZoneEntry] {
        try entries(zone: .trash)
    }

    private enum Zone: String {
        case disabled
        case trash
    }

    private func root(zone: Zone, agentID: AgentID) -> URL {
        zone == .disabled ? disabledRoot(agentID: agentID) : trashRoot(agentID: agentID)
    }

    /// 区内实际存在的 agent 目录（目录枚举——不依赖任何名单）。
    /// 回归背景：旧实现只遍历 `knownAgentIDs`，qwen/cursor/自定义 agent 的条目会「磁盘上有、UI 里没有」。
    private func zoneAgentIDs(_ zone: Zone) -> [AgentID] {
        let zoneRoot = baseDirectory.appendingPathComponent(zone.rawValue, isDirectory: true)
        let entries = (try? fileManager.contentsOfDirectory(atPath: zoneRoot.path)) ?? []
        var ids = Set<AgentID>()
        for name in entries {
            var isDirectory: ObjCBool = false
            let path = zoneRoot.appendingPathComponent(name, isDirectory: true).path
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                ids.insert(name)
            }
        }
        // 名单仅作兜底并集（旧 API 语义保留）
        ids.formUnion(knownAgentIDs)
        ids.insert("unknown")
        return ids.sorted()
    }

    private func entries(zone: Zone) throws -> [ZoneEntry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [ZoneEntry] = []
        for agentID in zoneAgentIDs(zone) {
            let agentRoot = root(zone: zone, agentID: agentID)
            guard let manifests = try? fileManager.contentsOfDirectory(atPath: agentRoot.path) else {
                continue
            }
            for manifest in manifests.sorted() where manifest.hasSuffix(".manifest.json") {
                let manifestURL = agentRoot.appendingPathComponent(manifest)
                guard let data = try? Data(contentsOf: manifestURL),
                      let record = try? decoder.decode(DisabledSkillRecord.self, from: data)
                else { continue }
                let name = String(manifest.dropLast(".manifest.json".count))
                let directory = agentRoot.appendingPathComponent(name, isDirectory: true)
                guard fileManager.fileExists(atPath: directory.path) else { continue }
                result.append(ZoneEntry(record: record, directoryPath: directory.path, manifestPath: manifestURL.path))
            }
        }
        return result
    }

    // MARK: - 回收站区（删除语义：原样保全、可回滚、可彻底清除）

    /// 回收站根（<base>/trash/——与停用区并行的第二个安全目录）。
    private func trashRoot(agentID: AgentID) -> URL {
        baseDirectory.appendingPathComponent("trash", isDirectory: true)
            .appendingPathComponent(agentID, isDirectory: true)
    }

    /// 删除（回收站语义）：原子搬入 trash + manifest 写盘；冲突/占用一律中止，绝不覆盖。
    @discardableResult
    public func moveToTrash(agentID: AgentID, skillDirectory: URL) throws -> DisabledSkillRecord {
        try moveToZone(.trash, agentID: agentID, skillDirectory: skillDirectory)
    }

    /// 从回收站恢复：按 manifest 原路径放回；原路径被占 → 中止零覆盖。
    @discardableResult
    public func restoreFromTrash(agentID: AgentID, name: String) throws -> DisabledSkillRecord {
        try restoreFromZone(.trash, agentID: agentID, name: name)
    }

    /// 彻底删除单个回收站条目（目录 + manifest 一并；其它条目不受牵连）。
    @discardableResult
    public func purgeTrash(agentID: AgentID, name: String) throws -> DisabledSkillRecord {
        let agentRoot = trashRoot(agentID: agentID)
        let manifestURL = agentRoot.appendingPathComponent("\(name).manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SkillLifecycleError.manifestMissing(path: manifestURL.path)
        }
        guard let record = try? Self.decodeRecord(from: manifestURL, fileManager: fileManager) else {
            throw SkillLifecycleError.manifestCorrupted(path: manifestURL.path)
        }
        let directory = agentRoot.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else {
            throw SkillLifecycleError.sourceMissing(path: directory.path)
        }
        try fileManager.removeItem(at: directory)
        try fileManager.removeItem(at: manifestURL)
        if (try? fileManager.contentsOfDirectory(atPath: agentRoot.path))?.isEmpty == true {
            try? fileManager.removeItem(at: agentRoot)
        }
        return record
    }

    /// 清空回收站：逐条彻底删除；返回清除数。空回收站为 0（幂等）。
    public func purgeAllTrash() throws -> Int {
        var purged = 0
        for entry in try trashEntries() {
            let agentRoot = trashRoot(agentID: entry.record.agentID)
            try fileManager.removeItem(atPath: entry.directoryPath)
            try fileManager.removeItem(atPath: entry.manifestPath)
            if (try? fileManager.contentsOfDirectory(atPath: agentRoot.path))?.isEmpty == true {
                try? fileManager.removeItem(at: agentRoot)
            }
            purged += 1
        }
        return purged
    }

    // MARK: - 私有：区通用搬移 / 恢复（disable↔trash 同构复用）

    private func moveToZone(_ zone: Zone, agentID: AgentID, skillDirectory: URL) throws -> DisabledSkillRecord {
        guard fileManager.fileExists(atPath: skillDirectory.path) else {
            throw SkillLifecycleError.sourceMissing(path: skillDirectory.path)
        }
        let name = skillDirectory.lastPathComponent
        let destination = root(zone: zone, agentID: agentID).appendingPathComponent(name, isDirectory: true)
        let destinationParent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationParent, withIntermediateDirectories: true)

        let sha = Fingerprint.sha256OfDirectory(skillDirectory) ?? ""
        let record = DisabledSkillRecord(
            originalPath: skillDirectory.path,
            agentID: agentID,
            name: name,
            sha256: sha
        )

        do {
            // sha 单次计算透传 planMove（免第二次全树哈希）
            let plan = try mover.planMove(source: skillDirectory, destination: destination, expectedSha256: sha)
            try mover.execute(plan)
        } catch {
            // 冲突明细透传给 UI（AtomicMoverError 与 LifecycleError 语义一致时）
            throw translate(error, path: destination.path)
        }

        // manifest 与目录同放（.manifest.json 同级——disable 与 trash 惯例一致）
        let manifestURL = root(zone: zone, agentID: agentID).appendingPathComponent("\(name).manifest.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: manifestURL, options: .atomic)
        } catch {
            // manifest 写失败等于入区不完整：回滚目录，报告
            try? mover.rollback(MovePlan(
                source: skillDirectory,
                destination: destination,
                strategy: .rename,
                expectedSha256: sha
            ))
            throw SkillLifecycleError.underlying(path: manifestURL.path, note: "\(error)")
        }
        return record
    }

    private static func decodeRecord(from url: URL, fileManager: FileManager) throws -> DisabledSkillRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DisabledSkillRecord.self, from: Data(contentsOf: url))
    }

    private func restoreFromZone(_ zone: Zone, agentID: AgentID, name: String) throws -> DisabledSkillRecord {
        let manifestURL = root(zone: zone, agentID: agentID).appendingPathComponent("\(name).manifest.json")
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw SkillLifecycleError.manifestMissing(path: manifestURL.path)
        }
        let record = try Self.decodeRecord(from: manifestURL, fileManager: fileManager)

        let zoneDirectory = root(zone: zone, agentID: agentID).appendingPathComponent(name, isDirectory: true)
        let original = URL(fileURLWithPath: record.originalPath, isDirectory: true)

        guard fileManager.fileExists(atPath: zoneDirectory.path) else {
            throw SkillLifecycleError.sourceMissing(path: zoneDirectory.path)
        }
        guard !fileManager.fileExists(atPath: original.path) else {
            // 冲突面板核心诉求：区目录与原路径占用明细一起呈现
            throw SkillLifecycleError.destinationOccupied(path: original.path)
        }
        try fileManager.createDirectory(
            at: original.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            let plan = try mover.planMove(source: zoneDirectory, destination: original)
            try mover.execute(plan)
        } catch {
            throw translate(error, path: original.path)
        }

        try? FileManager.default.removeItem(at: manifestURL)
        // 区 agent 目录空了顺手清掉，保持整区整洁
        let agentRoot = root(zone: zone, agentID: agentID)
        if (try? FileManager.default.contentsOfDirectory(atPath: agentRoot.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: agentRoot)
        }
        return record
    }

    // MARK: - 崩溃演练（7.3）

    /// 禁用区巡检：manifest 缺失的"未知禁用目录"（kill -9 搬入后 manifest 未写）。
    /// 列表供 UI 引导用户处置，绝不自动删除（数据零丢失）。
    public struct UnknownDisabledEntry: Hashable, Sendable {
        public var agentID: AgentID
        public var name: String
        public var path: String
    }

    public func unknownDisabledEntries() -> [UnknownDisabledEntry] {
        var unknown: [UnknownDisabledEntry] = []
        for agentID in zoneAgentIDs(.disabled) {
            let agentRoot = disabledRoot(agentID: agentID)
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: agentRoot.path) else {
                continue
            }
            for child in children where !child.hasSuffix(".manifest.json") {
                let url = agentRoot.appendingPathComponent(child, isDirectory: true)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    continue
                }
                let manifest = agentRoot.appendingPathComponent("\(child).manifest.json")
                guard !FileManager.default.fileExists(atPath: manifest.path) else { continue }
                unknown.append(UnknownDisabledEntry(agentID: agentID, name: child, path: url.path))
            }
        }
        return unknown
    }

    /// 幂等清理孤儿 manifest：disabled 目录已不存在（恢复已完成/中断）时，manifest 残留即垃圾。
    /// 返回清理数量；内容已回原位，零丢失。
    public func cleanupOrphanManifests() throws -> Int {
        var removed = 0
        for agentID in zoneAgentIDs(.disabled) {
            let agentRoot = disabledRoot(agentID: agentID)
            guard let children = try? FileManager.default.contentsOfDirectory(atPath: agentRoot.path) else {
                continue
            }
            for child in children where child.hasSuffix(".manifest.json") {
                let name = String(child.dropLast(".manifest.json".count))
                let disabledDir = agentRoot.appendingPathComponent(name, isDirectory: true)
                guard !FileManager.default.fileExists(atPath: disabledDir.path) else { continue }
                try FileManager.default.removeItem(at: agentRoot.appendingPathComponent(child))
                removed += 1
            }
        }
        return removed
    }

    // MARK: - 路径契约

    public func disabledRoot(agentID: AgentID) -> URL {
        baseDirectory.appendingPathComponent("disabled", isDirectory: true)
            .appendingPathComponent(agentID, isDirectory: true)
    }

    // MARK: - 错误翻译

    private func translate(_ error: Error, path: String) -> SkillLifecycleError {
        switch error {
        case let move as AtomicMoverError:
            switch move {
            case let .sourceMissing(p):
                .sourceMissing(path: p)
            case let .destinationOccupied(p):
                .destinationOccupied(path: p)
            case let .destinationParentMissing(p):
                .destinationParentMissing(path: p)
            case let .underlying(p, note):
                .underlying(path: p, note: note)
            default:
                .underlying(path: path, note: "\(move)")
            }
        default:
            .underlying(path: path, note: "\(error)")
        }
    }
}
