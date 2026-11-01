import Foundation
import DomainKit
import InfraKit

/// 外部变更全链路编排：
/// FSEvents 事件 → changePending 计数 → debounce 聚合 → 增量重扫 → catalog 快照同步（fs 为准）。
@MainActor
public final class ChangePipeline {
    private let store: AppStore
    private let catalogStore: CatalogStore
    private let scanService: ScanService
    private let debounceNanos: UInt64

    private var rescanTask: Task<Void, Never>?
    private var pendingEvents: [String] = []

    public init(
        store: AppStore,
        catalogStore: CatalogStore,
        scanService: ScanService,
        debounceNanos: UInt64 = 500_000_000
    ) {
        self.store = store
        self.catalogStore = catalogStore
        self.scanService = scanService
        self.debounceNanos = debounceNanos
    }

    /// 开始监听当前 agent 的全部 skill 根目录。
    public func attach(monitor: FileMonitoring) async {
        var unique: [URL] = []
        for root in store.state.agents.flatMap(\.skillRoots) where !unique.contains(root.path) {
            unique.append(root.path)
        }
        await monitor.start(watchingRoots: unique)
    }

    /// 单个事件入口（monitor 回调）。
    public func onEvent(rootPath: String) async {
        pendingEvents.append(rootPath)
        await store.dispatch(.externalChangeDetected(paths: [rootPath]))
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: self.debounceNanos)
            } catch {
                return  // 被更新的事件取消
            }
            await self.rescanNow()
        }
    }

    /// 测试/同步等待：等待进行中的 rescan 或没有进行者。
    public func flushForTesting() async {
        if let task = rescanTask {
            await task.value
            self.rescanTask = nil
        }
    }

    /// 立即重扫并按磁盘真相同步 catalog。
    /// runner（CatalogSyncingRunner）内部已做 build + sync——这里不再重复第二遍
    /// 全树遍历/哈希（曾使每次外部变更的全量成本 ×2，且第二遍压在 MainActor）。
    public func rescanNow() async {
        pendingEvents.removeAll()
        await scanService.runScan(projectRoots: [])
    }
}
