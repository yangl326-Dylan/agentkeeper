import Foundation
import DomainKit

/// 删除确认流转结果（UI 状态机消费）。
public struct DeletionPlan: Sendable, Hashable {
    public var confirmed: Bool
    /// 确认清单里的路径明细（对话框展示用）。
    public var paths: [String]
}

/// 删除类操作的统一确认门：
/// 空选择短路不弹窗；弹窗携带完整路径清单；取消则不执行任何动作。
public struct DeletionGate: Sendable {
    public init() {}

    public func requestDeletion(
        skills: [Skill],
        confirm: ([Skill]) -> Bool,
        perform: ([URL]) throws -> Void
    ) throws -> DeletionPlan {
        guard !skills.isEmpty else {
            return DeletionPlan(confirmed: false, paths: [])
        }
        let paths = skills.map { $0.directory.standardizedFileURL.path }
        guard confirm(skills) else {
            return DeletionPlan(confirmed: false, paths: paths)
        }
        try perform(skills.map { $0.directory.standardizedFileURL })
        return DeletionPlan(confirmed: true, paths: paths)
    }
}
