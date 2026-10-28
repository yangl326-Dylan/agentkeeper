import Foundation
import DomainKit

/// 操作方向（skill-lifecycle spec 的历史语义）。
public enum OperationDirection: String, Codable, Hashable, Sendable {
    case disable
    case enable
    case snapshotRestore
    case delete
    /// 分发安装/导入/git 来源安装（Phase 2）。
    case distribute
    /// 以选定版本更新同名铺设的全部落点（Phase 2）。
    case updateLandingPoints
}

/// 操作结果。
public enum OperationResult: Codable, Hashable, Sendable {
    case success
    case failure(message: String)

    private enum CodingKeys: String, CodingKey { case kind, message }
    private enum Kind: String, Codable { case success, failure }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .success:
            self = .success
        case .failure:
            self = .failure(message: try container.decode(String.self, forKey: .message))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .success:
            try container.encode(Kind.success, forKey: .kind)
        case let .failure(message):
            try container.encode(Kind.failure, forKey: .kind)
            try container.encode(message, forKey: .message)
        }
    }
}

/// 单条历史记录。
public struct OperationRecord: Codable, Hashable, Sendable {
    public var skillID: String
    public var name: String
    public var direction: OperationDirection
    public var result: OperationResult
    public var performedAt: Date

    public init(skillID: String, name: String, direction: OperationDirection, result: OperationResult, performedAt: Date = Date()) {
        self.skillID = skillID
        self.name = name
        self.direction = direction
        self.result = result
        self.performedAt = performedAt
    }
}

/// 操作历史（JSON 文件持久化，最新在前；损坏自愈为空并继续可写）。
public final class OperationHistory: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "agentkeeper.operationhistory")
    private var records: [OperationRecord]

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("history.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode([OperationRecord].self, from: data) {
                self.records = decoded
            } else {
                self.records = []
            }
        } else {
            self.records = []
        }
    }

    public func append(skillID: String, name: String, direction: OperationDirection, result: OperationResult) {
        queue.sync {
            records.insert(OperationRecord(
                skillID: skillID,
                name: name,
                direction: direction,
                result: result
            ), at: 0)
            persistLocked()
        }
    }

    /// 最近记录（最新的在前）。
    public func recent(limit: Int) -> [OperationRecord] {
        queue.sync {
            Array(records.prefix(max(0, limit)))
        }
    }

    private func persistLocked() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(records) {
            // 原子覆盖写盘；写失败仅影响持久化，内存记录仍可用
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
