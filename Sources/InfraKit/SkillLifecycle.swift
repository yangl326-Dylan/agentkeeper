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
    private let mover: AtomicMover
    private let fileManager: FileManager

    public init(baseDirectory: URL, mover: AtomicMover = AtomicMover()) {
        self.baseDirectory = baseDirectory
        self.mover = mover
        self.fileManager = .default
    }

    /// 禁用：原子搬移至禁用区 + manifest 写盘。冲突/占用一律中止，绝不覆盖。
    @discardableResult
    public func disable(agentID: AgentID, skillDirectory: URL) throws -> DisabledSkillRecord {
        guard fileManager.fileExists(atPath: skillDirectory.path) else {
            throw SkillLifecycleError.sourceMissing(path: skillDirectory.path)
        }
        let name = skillDirectory.lastPathComponent
        let destination = destinationURL(agentID: agentID, name: name)
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
            let plan = try mover.planMove(source: skillDirectory, destination: destination)
            try mover.execute(plan)
        } catch {
            // 冲突明细透传给 UI（AtomicMoverError 与 LifecycleError 语义一致时）
            throw translate(error, path: destination.path)
        }

        // manifest 放禁用目录旁（.manifest.json），与目录强关联
        let manifestURL = disabledRoot(agentID: agentID).appendingPathComponent("\(name).manifest.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: manifestURL, options: .atomic)
        } catch {
            // manifest 写失败等于禁用不完整：回滚目录，报告
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

    // MARK: - 恢复（4.3）

    /// 恢复：按 manifest 回原路径。原路径被占 → 中止并输出冲突明细，绝不覆盖。
    /// 成功后清理 manifest 与（已空的）禁用目录。
    @discardableResult
    public func enable(agentID: AgentID, name: String) throws -> DisabledSkillRecord {
        let manifestURL = disabledRoot(agentID: agentID).appendingPathComponent("\(name).manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw SkillLifecycleError.manifestMissing(path: manifestURL.path)
        }
        let record: DisabledSkillRecord
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            record = try decoder.decode(DisabledSkillRecord.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw SkillLifecycleError.manifestCorrupted(path: manifestURL.path)
        }

        let disabledDir = destinationURL(agentID: agentID, name: name)
        let original = URL(fileURLWithPath: record.originalPath, isDirectory: true)

        guard fileManager.fileExists(atPath: disabledDir.path) else {
            throw SkillLifecycleError.sourceMissing(path: disabledDir.path)
        }
        guard !fileManager.fileExists(atPath: original.path) else {
            // 冲突面板核心诉求：禁用区与原路径占用明细一起呈现
            throw SkillLifecycleError.destinationOccupied(path: original.path)
        }
        try fileManager.createDirectory(
            at: original.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            let plan = try mover.planMove(source: disabledDir, destination: original)
            try mover.execute(plan)
        } catch {
            throw translate(error, path: original.path)
        }

        try? FileManager.default.removeItem(at: manifestURL)
        // disabled/<agent> 空了顺手清掉，保持禁用区整洁
        let agentDisabledRoot = disabledRoot(agentID: agentID)
        if (try? FileManager.default.contentsOfDirectory(atPath: agentDisabledRoot.path))?.isEmpty == true {
            try? FileManager.default.removeItem(at: agentDisabledRoot)
        }
        return record
    }

    // MARK: - 路径契约

    public func disabledRoot(agentID: AgentID) -> URL {
        baseDirectory.appendingPathComponent("disabled", isDirectory: true)
            .appendingPathComponent(agentID, isDirectory: true)
    }

    public func destinationURL(agentID: AgentID, name: String) -> URL {
        disabledRoot(agentID: agentID).appendingPathComponent(name, isDirectory: true)
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
