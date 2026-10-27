import Foundation
import DomainKit
import InfraKit

/// 操作执行的底层错误（UI 冲突面板直接吃 detail）。
public enum OperationError: Error, Hashable {
    case conflict(detail: String)
    case underlying(detail: String)
}

/// 生命周期操作编排。
/// 状态机：operationStarted → 执行 → 完成后自动重扫 / 失败即止不重扫。
/// AppUpdate 每一步都经 dispatch 广播（AppStore 单出口）。
@MainActor
public final class OperationService {
    private let store: AppStore
    private let scanService: ScanService
    private let performer: @Sendable (Skill, OperationDirection) async throws -> Void

    public init(
        store: AppStore,
        scanService: ScanService,
        performer: @escaping @Sendable (Skill, OperationDirection) async throws -> Void
    ) {
        self.store = store
        self.scanService = scanService
        self.performer = performer
    }

    /// 执行一个操作（禁用/恢复），全程推进状态机。
    public func run(skill: Skill, direction: OperationDirection) async {
        await store.dispatch(.operationStarted(skillID: skill.id, direction: direction))
        do {
            try await performer(skill, direction)
            await store.dispatch(.operationCompleted(skillID: skill.id, direction: direction))
            // 完成即触发重扫刷新 catalog（MVP 全量重扫路径由 scanService 提供）
            await scanService.runScan(projectRoots: [])
        } catch let operationError as OperationError {
            let message: String
            switch operationError {
            case let .conflict(detail): message = detail
            case let .underlying(detail): message = detail
            }
            await store.dispatch(.operationFailed(
                skillID: skill.id,
                direction: direction,
                message: message
            ))
        } catch {
            await store.dispatch(.operationFailed(
                skillID: skill.id,
                direction: direction,
                message: "\(error)"
            ))
        }
    }
}
