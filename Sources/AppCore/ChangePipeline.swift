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

    /// 事件过滤：自建目录的过渡文件不触发全量重扫——install staging（.ak-stage-）、
    /// 禁用/快照让位（.ak-old-）、备份区（.keeper-backup-）写盘曾被 FSEvents 弹回
    /// 全量重扫（自反馈扫描风暴）。按路径组件 basename 前缀判（嵌套深层也拦）。
    private static let transientPrefixes = [".ak-stage-", ".ak-old-", ".keeper-backup-"]

    static func isTransientEvent(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        return components.contains { component in
            transientPrefixes.contains { component.hasPrefix($0) }
        }
    }

    /// FSEvents 整批入口（monitor 单批回调）：一次 pending 记账 + 一次 dispatch +
    /// 一次防抖重挂（曾每路径一枚 Task + 一次 dispatch——风暴时数百 Task/秒）。
    public func onEvents(paths: [String]) async {
        let filtered = paths.filter { !Self.isTransientEvent($0) }
        guard !filtered.isEmpty else { return }
        pendingEvents.append(contentsOf: filtered)
        await store.dispatch(.externalChangeDetected(paths: filtered))
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

    /// 单个事件入口（monitor 回调）——兼容单参（fake monitor / 测试用 ; 生产走 onEvents）。
    public func onEvent(rootPath: String) async {
        guard !Self.isTransientEvent(rootPath) else { return }
        await onEvents(paths: [rootPath])
    }

    /// 测试/同步等待：等待进行中的 rescan 或没有进行者。
    public func flushForTesting() async {
        if let task = rescanTask {
            await task.value
            self.rescanTask = nil
        }
    }

    /// 立即重扫并按磁盘真相同步 catalog。
    /// runner（CatalogSyncingRunner）内部已做 build + sync——不再重复第二遍
    /// 全树遍历/哈希。门禁在途时：等待收敛后补一扫（在途快照不含这批事件）。
    public func rescanNow() async {
        let executed = await scanService.runScan(projectRoots: [])
        if !executed {
            _ = await scanService.runScan(projectRoots: [])
        }
        pendingEvents.removeAll()
    }
}
