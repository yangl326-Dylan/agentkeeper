import Foundation
import DomainKit
import InfraKit

/// 落点更新的失败明细。
public struct FailedLandingPoint: Hashable, Sendable {
    public var point: LandingPoint
    public var message: String

    public init(point: LandingPoint, message: String) {
        self.point = point
        self.message = message
    }
}

/// 「以此版本更新所有落点」的汇总：成功落点 / 禁用跳过 / 失败明细（部分成功允许）。
public struct LandingPointsUpdateSummary: Sendable, Hashable {
    public var updated: [LandingPoint]
    public var skippedDisabled: [LandingPoint]
    public var failures: [FailedLandingPoint]

    public init(
        updated: [LandingPoint] = [],
        skippedDisabled: [LandingPoint] = [],
        failures: [FailedLandingPoint] = []
    ) {
        self.updated = updated
        self.skippedDisabled = skippedDisabled
        self.failures = failures
    }

    public var isFullyFailed: Bool {
        updated.isEmpty && !failures.isEmpty
    }

    var failureDetail: String {
        failures.map { "\($0.point.agentID)：\($0.message)" }.joined(separator: "；")
    }
}

/// 分发编排（design D2/D6）：接入操作状态机，落点更新逐个执行并有快照兜底。
@MainActor
public final class DistributionService {
    private let store: AppStore
    private let snapshotService: SnapshotService
    private let history: OperationHistory
    private let distributor: SkillDistributor
    private let disabledRoot: URL
    private let catalogProvider: @Sendable () -> [Skill]
    private let rescan: @Sendable () async -> Void

    public init(
        store: AppStore,
        snapshotService: SnapshotService,
        history: OperationHistory,
        distributor: SkillDistributor,
        disabledRoot: URL,
        catalogProvider: @escaping @Sendable () -> [Skill] = { [] },
        rescan: @escaping @Sendable () async -> Void
    ) {
        self.store = store
        self.snapshotService = snapshotService
        self.history = history
        self.distributor = distributor
        self.disabledRoot = disabledRoot
        self.catalogProvider = catalogProvider
        self.rescan = rescan
    }

    /// 以 baseline（同名铺设中的选定版本）更新其余同名落点。
    /// 每个落点先自动快照当前内容再覆盖；禁用区落点跳过并列入明细。
    public func updateAllLandingPoints(from baseline: Skill) async -> LandingPointsUpdateSummary {
        await store.dispatch(.operationStarted(skillID: baseline.id, direction: .updateLandingPoints))

        let catalog = catalogProvider()
        let byDirectory = Dictionary(
            uniqueKeysWithValues: catalog.map { ($0.directory.standardizedFileURL.path, $0) }
        )
        let candidates = CatalogQuery.namedLandingPoints(
            named: baseline.name,
            catalog: catalog
        ).filter { $0.directory.standardizedFileURL.path != baseline.directory.standardizedFileURL.path }

        var summary = LandingPointsUpdateSummary()
        for point in candidates {
            // 禁用区落点不接触（恢复走 enable 流程）
            if isDisabledArea(point.directory) {
                summary.skippedDisabled.append(point)
                continue
            }
            guard let skillEntity = byDirectory[point.directory.standardizedFileURL.path] else {
                summary.failures.append(FailedLandingPoint(point: point, message: "落点不在 catalog 中"))
                continue
            }
            do {
                // 1. 自动快照兜底（同指纹幂等 no-op）
                try await snapshotService.autoSnapshot(skill: skillEntity, directory: skillEntity.directory)
                // 2. 覆盖（失败自动回滚让位）
                try await Task.detached(priority: .userInitiated) { [distributor] in
                    try distributor.replaceDirectoryContent(
                        target: skillEntity.directory.standardizedFileURL,
                        sourceDirectory: baseline.directory.standardizedFileURL
                    )
                }.value
                summary.updated.append(point)
                history.append(
                    skillID: skillEntity.id,
                    name: skillEntity.name,
                    direction: .updateLandingPoints,
                    result: .success
                )
            } catch {
                let message = "\(error)"
                summary.failures.append(FailedLandingPoint(point: point, message: message))
                history.append(
                    skillID: skillEntity.id,
                    name: skillEntity.name,
                    direction: .updateLandingPoints,
                    result: .failure(message: message)
                )
            }
        }

        if summary.failures.isEmpty {
            await store.dispatch(.operationCompleted(
                skillID: baseline.id, direction: .updateLandingPoints
            ))
        } else {
            await store.dispatch(.operationFailed(
                skillID: baseline.id,
                direction: .updateLandingPoints,
                message: summary.failureDetail
            ))
        }
        await rescan()
        return summary
    }

    private func isDisabledArea(_ directory: URL) -> Bool {
        let resolved = directory.standardizedFileURL.path
        let root = disabledRoot.standardizedFileURL.path
        return resolved == root || resolved.hasPrefix(root + "/")
    }
}
