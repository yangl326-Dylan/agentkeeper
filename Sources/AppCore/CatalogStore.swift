import Foundation
import DomainKit
import InfraKit

/// 内存 catalog 快照 + SQLite 缓存联动。
/// 磁盘是唯一真相：每次 sync 都会全量覆盖缓存（外部变更导致失真时自动纠偏）。
@MainActor
@Observable
public final class CatalogStore {
    public private(set) var current: [Skill]
    private let index: SkillIndex?

    public init(index: SkillIndex? = nil, initial: [Skill] = []) {
        self.index = index
        // 启动时先用缓存填充（网络/扫描未完成前 UI 有内容），随后增量扫描纠偏
        if let cached = index?.all() {
            self.current = cached
        } else {
            self.current = initial
        }
    }

    /// 与最近一次扫描结果对齐（磁盘真相下发到快照与缓存）。
    public func sync(with skills: [Skill]) {
        current = skills
        index?.replaceAll(skills)
    }
}
