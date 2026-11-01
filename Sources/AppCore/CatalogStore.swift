import Foundation
import DomainKit
import InfraKit

/// 内存 catalog 快照 + SQLite 缓存联动。
/// 磁盘是唯一真相：每次 sync 都会全量覆盖缓存（外部变更导致失真时自动纠偏）。
@MainActor
@Observable
public final class CatalogStore {
    public private(set) var current: [Skill]
    /// 内容单调版本号（每次快照变化自增）——派生数据（侧栏/总览行模型）
    /// 以此为 key 缓存，避免每次 body 求值重新 O(skills) 全量计算。
    public private(set) var version: Int = 0
    private let index: SkillIndex?

    public init(index: SkillIndex? = nil, initial: [Skill] = [], loadCacheEagerly: Bool = true) {
        self.index = index
        // 默认：启动时先用缓存填充（网络/扫描未完成前 UI 有内容），随后增量扫描纠偏；
        // loadCacheEagerly=false：init 不读盘（AppEnvironment 首屏装配零 IO），bootstrap 时 warmupFromCache 后台回填
        if loadCacheEagerly, let cached = index?.all() {
            self.current = cached
        } else {
            self.current = initial
        }
    }

    /// 后台加载 SQLite 缓存并回填（仅当 current 为空——扫描结果优先，磁盘真相不倒灌）。
    public func warmupFromCache() async {
        guard let index, current.isEmpty else { return }
        let cached = await Task.detached(priority: .userInitiated) { [index] in
            index.all()
        }.value
        if current.isEmpty {
            current = cached
            version += 1
        }
    }

    /// 与最近一次扫描结果对齐（磁盘真相下发到快照与缓存）。
    /// 内存快照同步即回（主线程）；索引写盘走后台队列（不阻塞 MainActor——
    /// 曾此处同步写 SQLite 每次外部变更都钉住主线程）。
    public func sync(with skills: [Skill]) {
        current = skills
        version += 1
        index?.replace(skills)
    }
}
