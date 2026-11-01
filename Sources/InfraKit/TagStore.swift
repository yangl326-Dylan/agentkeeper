import Foundation
import DomainKit

/// 用户自定义标签（design D4）：单一 JSON 存储 + 原子写 + 损坏自愈。
/// assignment key = skill 的 skillID（路径确定：禁用/启用恢复同路径 → 关联稳定）。
public final class TagStore: @unchecked Sendable {
    public struct Payload: Codable, Sendable, Hashable {
        /// 标签定义（去重）。
        public var tags: [String]
        /// skillID → 标签名集合。
        public var assignments: [String: Set<String>]

        public init(tags: [String] = [], assignments: [String: Set<String>] = [:]) {
            self.tags = tags
            self.assignments = assignments
        }
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "agentkeeper.tagstore")
    private var payload: Payload
    /// 每次写盘后自增（UI/派生数据缓存失效用）。
    public private(set) var revision: Int = 0

    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("tags.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(Payload.self, from: data) {
                self.payload = Self.normalized(decoded)
                return
            }
            // 损坏：备份后自愈为空
            let backup = directory.appendingPathComponent(
                "tags.json.corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? data.write(to: backup, options: .atomic)
        }
        self.payload = Payload()
    }

    // MARK: - 定义

    /// 全部标签定义（排序）。
    public func tags() -> [String] {
        queue.sync { payload.tags.sorted() }
    }

    /// 新增定义（幂等）。空名拒绝。
    @discardableResult
    public func addDefinition(_ tag: String) -> Bool {
        let name = tag.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        queue.sync {
            if !payload.tags.contains(name) { payload.tags.append(name) }
            persistLocked()
        }
        return true
    }

    /// 删除定义：同时清掉其全部关联（不影响 skill 文件）。
    public func removeDefinition(_ tag: String) {
        queue.sync {
            payload.tags.removeAll { $0 == tag }
            payload.assignments = payload.assignments.mapValues { set in
                var s = set
                s.remove(tag)
                return s
            }
            payload.assignments = payload.assignments.filter { !$0.value.isEmpty }
            persistLocked()
        }
    }

    /// 重命名：定义与全部关联同步。
    public func rename(_ from: String, to new: String) {
        let name = new.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != from else { return }
        queue.sync {
            guard payload.tags.contains(from) else { return }
            payload.tags.removeAll { $0 == from }
            if !payload.tags.contains(name) { payload.tags.append(name) }
            payload.assignments = payload.assignments.mapValues { set in
                var s = set
                if s.remove(from) != nil { s.insert(name) }
                return s
            }
            persistLocked()
        }
    }

    // MARK: - 关联

    /// 把标签指给 skill（标签必须已定义）。返回是否成功。
    @discardableResult
    public func assign(tag: String, skillID: String) -> Bool {
        queue.sync {
            guard payload.tags.contains(tag) else { return false }
            payload.assignments[skillID, default: []].insert(tag)
            persistLocked()
            return true
        }
    }

    public func unassign(tag: String, skillID: String) {
        queue.sync {
            if var set = payload.assignments[skillID] {
                set.remove(tag)
                if set.isEmpty {
                    payload.assignments[skillID] = nil
                } else {
                    payload.assignments[skillID] = set
                }
            }
            persistLocked()
        }
    }

    /// 某标签的全部关联 skillID。
    public func assignments(tag: String) -> [String] {
        queue.sync {
            payload.assignments
                .filter { $0.value.contains(tag) }
                .map(\.key)
        }
    }

    /// 某 skill 携带的全部标签。
    public func tags(forSkillID skillID: String) -> [String] {
        queue.sync {
            Array(payload.assignments[skillID] ?? []).sorted()
        }
    }

    /// 全部被参与关联的 skillID（orphan 判定用）。
    public func allAssignedSkillIDs() -> [String] {
        queue.sync { Array(payload.assignments.keys) }
    }

    // MARK: - 自愈

    private static func normalized(_ payload: Payload) -> Payload {
        var result = payload
        result.tags = Array(Set(result.tags.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }))
        return result
    }

    private func persistLocked() {
        revision += 1
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// 全表标签映射快照（一次进队取完——供缓存派生，避免逐 skillID N 次锁往返）。
    public func assignedTagsBySkill() -> [String: [String]] {
        queue.sync {
            payload.assignments.mapValues { Array($0).sorted() }
        }
    }
}
