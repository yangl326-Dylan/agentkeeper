import Foundation
import DomainKit

/// 扫描编排：把扫描生命周期（开始→完成/失败）推入 store，UI 侧零感知并发细节。
@MainActor
public final class ScanService {
    private let store: AppStore
    private let runner: ScanRunning

    public init(store: AppStore, runner: ScanRunning) {
        self.store = store
        self.runner = runner
    }

    /// 执行一次全量扫描；用于首启、手动触发与菜单栏快捷扫描。
    public func runScan(projectRoots: [ProjectRoot] = []) async {
        await store.dispatch(.scanStarted)
        do {
            let report = try await runner.run(projectRoots: projectRoots)
            await store.dispatch(.scanCompleted(report))
        } catch {
            await store.dispatch(.scanFailed(message: errorFriendly(error)))
        }
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
