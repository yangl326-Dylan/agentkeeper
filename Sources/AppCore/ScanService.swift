import Foundation
import DomainKit

/// 扫描编排：把扫描生命周期（开始→完成/失败）推入 store，UI 侧零感知并发细节。
@MainActor
public final class ScanService {
    private let store: AppStore
    private let runner: ScanRunning
    private var inFlight = false
    private var inFlightWaiters: [CheckedContinuation<Void, Never>] = []

    public init(store: AppStore, runner: ScanRunning) {
        self.store = store
        self.runner = runner
    }

    /// 执行一次全量扫描；用于首启、手动触发与菜单栏快捷扫描。
    /// 重入门禁：扫描已在进行时**等待在途收敛后返回 false（未执行）**——
    /// menu 快捷键连点 / FSEvents 窗外扫描曾双开 runner（全树哈希双倍成本 + 状态抖动），
    /// 现在并发调用只有一个真正的 runner run，且调用方能够感知"未执行"以便补扫。
    @discardableResult
    public func runScan(projectRoots: [ProjectRoot] = []) async -> Bool {
        if inFlight {
            // 等待在途扫描收敛（MainActor 串行化下安全）
            await withCheckedContinuation { continuation in
                inFlightWaiters.append(continuation)
            }
            return false
        }
        inFlight = true
        defer {
            inFlight = false
            let waiters = inFlightWaiters
            inFlightWaiters = []
            for waiter in waiters { waiter.resume() }
        }
        await store.dispatch(.scanStarted)
        do {
            let report = try await runner.run(projectRoots: projectRoots)
            await store.dispatch(.scanCompleted(report))
        } catch {
            await store.dispatch(.scanFailed(message: errorFriendly(error)))
        }
        return true
    }

    /// 扫描范围（项目根）变化后的重扫入口（spec：范围变更 MUST 触发重新扫描）。
    public func rescanAfterScopeChange(added: [ProjectRoot] = []) async {
        await runScan(projectRoots: added)
    }

    private func errorFriendly(_ error: Error) -> String {
        if let access = error as? SkillAccessError {
            switch access {
            case let .permissionDenied(path):
                return "权限受限：\(path)"
            case let .ioFailure(path, underlying):
                return "IO 失败：\(path)（\(underlying)）"
            }
        }
        return "\(error)"
    }
}
