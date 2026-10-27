import Foundation
import AppCore
import DomainKit
import InfraKit
import SwiftUI
import AppKit

/// 应用组装根：真实 InfraKit/AppCore 服务在此拼装，UI 只依赖本环境。
@MainActor
@Observable
final class AppEnvironment {
    let store: AppStore
    let catalogStore: CatalogStore
    let scanService: ScanService
    let pipeline: ChangePipeline
    let operationService: OperationService
    let history: OperationHistory
    let snapshots: SnapshotStore
    let snapshotService: SnapshotService
    let lifecycle: SkillLifecycle

    /// 列表选中态（三面板共享）。
    var selectedSkillID: String?

    /// 真实数据根（~；测试版可注入其它 home）。
    private let homeDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
        let base = homeDirectory.appendingPathComponent(".agentkeeper", isDirectory: true)
        let store = AppStore()
        let catalogStore = CatalogStore(index: SkillIndex(databaseDirectory: base))
        let runner = CatalogSyncingRunner(
            upstream: InfraScanRunner(homeDirectory: homeDirectory, scopeBaseDirectory: base),
            catalogStore: catalogStore
        )
        let scanService = ScanService(store: store, runner: runner)
        let lifecycle = SkillLifecycle(baseDirectory: base)
        let history = OperationHistory(directory: base)
        let snapshots = SnapshotStore(baseDirectory: base)
        let operationService = OperationService(
            store: store,
            scanService: scanService,
            performer: { skill, direction in
                let mover = SkillLifecycle(baseDirectory: base)
                do {
                    switch direction {
                    case .disable:
                        _ = try mover.disable(
                            agentID: skill.owners.first ?? "unknown",
                            skillDirectory: skill.directory.standardizedFileURL
                        )
                    case .enable:
                        _ = try mover.enable(
                            agentID: skill.owners.first ?? "unknown",
                            name: skill.name
                        )
                    default:
                        throw OperationError.underlying(detail: "该操作类型由对应流程处理（MVP 菜单外）")
                    }
                } catch let error as SkillLifecycleError {
                    throw translateLifecycle(error)
                } catch {
                    throw OperationError.underlying(detail: "\(error)")
                }
            }
        )
        self.store = store
        self.catalogStore = catalogStore
        self.scanService = scanService
        self.pipeline = ChangePipeline(
            store: store,
            catalogStore: catalogStore,
            scanService: scanService,
            debounceNanos: 500_000_000
        )
        self.operationService = operationService
        self.history = history
        self.snapshots = snapshots
        self.snapshotService = SnapshotService(
            snapshots: snapshots,
            history: history,
            rescan: { [weak store, weak scanService] in
                guard let store, let scanService else { return }
                await MainActor.run {
                    Task { await scanService.runScan(projectRoots: []) }
                    _ = store
                }
            }
        )
        self.lifecycle = lifecycle
    }

    /// 首启：全量扫描 + 挂载 FSEvents 监听。
    func bootstrap() async {
        await scanService.runScan(projectRoots: [])
        let monitor = FSEventMonitor(latencySeconds: 0.5) { [weak self] event in
            let path = event.rootPath
            Task { @MainActor in
                await self?.pipeline.onEvent(rootPath: path)
            }
        }
        await pipeline.attach(monitor: monitor)
    }

    /// 立即扫描（主窗口/菜单栏共用）。
    func scanNow() async {
        await scanService.runScan(projectRoots: [])
    }

    /// 操作 + 历史落账。
    func runOperation(skill: Skill, direction: OperationDirection) async {
        await operationService.run(skill: skill, direction: direction)
        if let failure = store.state.operation.failureMessage {
            history.append(skillID: skill.id, name: skill.name, direction: direction, result: .failure(message: failure))
        } else {
            history.append(skillID: skill.id, name: skill.name, direction: direction, result: .success)
        }
    }

    /// 快照恢复（先快照当前 → 重建旧内容；失败回滚不丢数据）。
    func restoreSnapshot(skill: Skill, sha: String) async {
        await snapshotService.restore(skill: skill, sha: sha)
    }

    /// Reduce Motion 策略（跟随系统辅助功能设置）。
    var motionPolicy: MotionPolicy {
        MotionPolicy(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
}

private func translateLifecycle(_ error: SkillLifecycleError) -> OperationError {
    switch error {
    case let .sourceMissing(path):
        .underlying(detail: "源不存在：\(path)")
    case let .destinationOccupied(path):
        .conflict(detail: "目标路径被占用：\(path)（绝不覆盖，请处理后重试）")
    case let .destinationParentMissing(path):
        .underlying(detail: "目标父目录缺失：\(path)")
    case let .manifestMissing(path):
        .underlying(detail: "manifest 缺失：\(path)")
    case let .manifestCorrupted(path):
        .underlying(detail: "manifest 损坏：\(path)")
    case let .underlying(path, note):
        .underlying(detail: "操作失败：\(path)（\(note)）")
    }
}

/// 扫描后同步 catalog 快照的 runner 装饰器（ChangePipeline 与操作完成共用一条路径）。
final class CatalogSyncingRunner: ScanRunning, @unchecked Sendable {
    private let upstream: InfraScanRunner
    private let catalogStore: CatalogStore

    init(upstream: InfraScanRunner, catalogStore: CatalogStore) {
        self.upstream = upstream
        self.catalogStore = catalogStore
    }

    func run(projectRoots: [ProjectRoot]) async throws -> ScanReport {
        let report = try await upstream.run(projectRoots: projectRoots)
        let skills = CatalogBuilder().build(agents: report.agents)
        let store = catalogStore
        let snapshot = skills
        Task { @MainActor in
            store.sync(with: snapshot)
        }
        return report
    }
}
