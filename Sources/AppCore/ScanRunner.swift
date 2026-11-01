import Foundation
import DomainKit
import InfraKit

/// 扫描执行契约（AppCore 定义，测试可注入）。
public protocol ScanRunning: Sendable {
    func run(projectRoots: [ProjectRoot]) async throws -> ScanReport
}

/// InfraKit 组装：内置 7 adapter 调度器 + ScanScopeStore 用户项目根。
public struct InfraScanRunner: ScanRunning {
    /// 家目录（默认真实用户家；测试可注入）。
    private let homeDirectory: URL
    /// 扫描范围存储的位置（默认 ~/.agentkeeper）。
    private let scopeBaseDirectory: URL?

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        scopeBaseDirectory: URL? = nil
    ) {
        self.homeDirectory = homeDirectory
        self.scopeBaseDirectory = scopeBaseDirectory
    }

    public func run(projectRoots: [ProjectRoot]) async throws -> ScanReport {
        let registry = AgentRegistry(homeDirectory: homeDirectory)
        let scheduler = ScanScheduler(registry: registry)
        var mergedRoots = projectRoots
        if let base = scopeBaseDirectory, let store = try? ScanScopeStore(directory: base) {
            let userRoots = store.userProjectRoots()
            for userRoot in userRoots where !mergedRoots.contains(userRoot) {
                mergedRoots.append(userRoot)
            }
        }
        return await scheduler.scanAll(knownProjectRoots: mergedRoots)
    }
}

/// 扫描后同步 catalog 快照的 runner 装饰器（ChangePipeline 与操作完成共用一条路径）。
public final class CatalogSyncingRunner: ScanRunning, @unchecked Sendable {
    private let upstream: ScanRunning
    private let catalogStore: CatalogStore

    public init(upstream: ScanRunning, catalogStore: CatalogStore) {
        self.upstream = upstream
        self.catalogStore = catalogStore
    }

    public func run(projectRoots: [ProjectRoot]) async throws -> ScanReport {
        let report = try await upstream.run(projectRoots: projectRoots)
        let skills = CatalogBuilder().build(agents: report.agents)
        let store = catalogStore
        let snapshot = skills
        // 确定性同步 hop（Task 脱管会让 sync 与下游断言/读取产生竞态；sync 本身写库走索引队列不阻塞主线程）
        await MainActor.run {
            store.sync(with: snapshot)
        }
        return report
    }
}
