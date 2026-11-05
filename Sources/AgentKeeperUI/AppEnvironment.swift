import Foundation
import AppCore
import DomainKit
import InfraKit
import SwiftUI
import AppKit

/// 应用组装根：真实 InfraKit/AppCore 服务在此拼装，UI 只依赖本环境。
@MainActor
@Observable
public final class AppEnvironment {
    public let store: AppStore
    public let catalogStore: CatalogStore
    public let scanService: ScanService
    public let pipeline: ChangePipeline
    public let operationService: OperationService
    public let history: OperationHistory
    public let snapshots: SnapshotStore
    public let snapshotService: SnapshotService
    public let lifecycle: SkillLifecycle
    public let tagService: TagService
    public let distributionService: DistributionService

    /// 列表选中态（三面板共享）。
    public var selectedSkillID: String?

    /// 侧栏导航节点（导航视图：全侧栏单选；列表 = 节点集合 ∩ 搜索词）。
    public var selectedNode: SidebarNode = .all

    /// 切换节点（视图切换时清掉列表选中——新视图内可能不存在该 skill）。
    public func select(node: SidebarNode) {
        if selectedNode != node {
            selectedSkillID = nil
        }
        selectedNode = node
    }

    /// 区内容版本号（任何区操作后自增）——侧栏计数与区列表以此为失效键，
    /// 避免逐帧枚举 manifest（fs IO）。
    public var zoneRevision: Int = 0

    @ObservationIgnored private var zoneCache: (revision: Int, disabled: [ZoneRowModel], trashed: [ZoneRowModel])?

    /// 停用区行（memoize；zoneRevision 变更后重枚举）。
    public func disabledZoneRows() -> [ZoneRowModel] {
        zoneRows(zone: .disabled)
    }

    /// 回收站行（memoize 同上）。
    public func trashedZoneRows() -> [ZoneRowModel] {
        zoneRows(zone: .trash)
    }

    private func zoneRows(zone: LifecycleZone) -> [ZoneRowModel] {
        if let cache = zoneCache, cache.revision == zoneRevision {
            return zone == .disabled ? cache.disabled : cache.trashed
        }
        let lifecycle = self.lifecycle
        let disabled = (try? lifecycle.disabledEntries()) ?? []
        let trashed = (try? lifecycle.trashEntries()) ?? []
        let disabledRows = ZoneListModel.build(entries: disabled)
        let trashedRows = ZoneListModel.build(entries: trashed)
        zoneCache = (zoneRevision, disabledRows, trashedRows)
        return zone == .disabled ? disabledRows : trashedRows
    }

    private func bumpZones() {
        zoneRevision += 1
    }

    /// 界面本地化（由 settings.language 驱动；@Observable 链——切换语言全 UI 即时刷新）。
    public var l10n: L10n {
        L10n.resolve(settings.language)
    }

    /// 首启引导完成标记（落盘：完成过不再出现，spec 6.6）。
    public var firstRun: FirstRunStore

    /// 引导页可见性（可观察；初始由落盘标记决定，「重新显示引导」/完成切换）。
    public var isOnboardingVisible: Bool

    /// 常见配置（外观/动效，落盘 defaults；Settings 场景读写这里）。
    public let settings: AppSettingsStore

    /// 设置页更新检查（仅手动触发；外部无红点/角标）。
    public let updates: UpdateModel

    /// 真实数据根（~；测试版可注入其它 home）。
    private let homeDirectory: URL
    private let akBase: URL

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        defaults: UserDefaults = .standard
    ) {
        self.homeDirectory = homeDirectory
        self.akBase = homeDirectory.appendingPathComponent(".agentkeeper", isDirectory: true)
        self.firstRun = FirstRunStore(defaults: defaults)
        self.settings = AppSettingsStore(defaults: defaults)
        self.updates = UpdateModel()
        let base = self.akBase
        let store = AppStore()
        // loadCacheEagerly=false：装配零 IO（SQLite 首读不再阻塞首屏）；bootstrap 后台 warmup
        let catalogStore = CatalogStore(index: SkillIndex(databaseDirectory: base), loadCacheEagerly: false)
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
                    case .delete:
                        // 删除 = 移入回收站（~/.agentkeeper/trash/<agent>/<skill>/
                        // + manifest），原样保全可回滚；彻底删除仅在区列表二次确认
                        _ = try mover.moveToTrash(
                            agentID: skill.owners.first ?? "unknown",
                            skillDirectory: skill.directory.standardizedFileURL
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
        self.tagService = TagService(
            store: TagStore(directory: base),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true)
        )
        let rescan: @Sendable () async -> Void = { [weak scanService] in
            guard let scanService else { return }
            await scanService.runScan(projectRoots: [])
        }
        self.distributionService = DistributionService(
            store: store,
            snapshotService: snapshotService,
            history: history,
            distributor: SkillDistributor(git: GitInstaller(baseDirectory: base)),
            disabledRoot: base.appendingPathComponent("disabled", isDirectory: true),
            catalogProvider: { [weak catalogStore] in
                catalogStore?.current ?? []
            },
            rescan: rescan
        )
        // 可观察属性在 init 完成前不走宏生成的 getter——用独立局部实例判断
        self.isOnboardingVisible = !FirstRunStore(defaults: defaults).hasCompletedOnboarding
    }

    /// 首启：后台预热缓存（UI 立即有内容）→ 全量扫描 + 挂载 FSEvents 监听（整批回调 → 一次 MainActor hop）。
    public func bootstrap() async {
        async let warmup: Void = catalogStore.warmupFromCache()
        await scanService.runScan(projectRoots: [])
        _ = await warmup
        let monitor = FSEventMonitor(latencySeconds: 0.5) { [weak self] paths in
            Task { @MainActor in
                await self?.pipeline.onEvents(paths: paths)
            }
        }
        await pipeline.attach(monitor: monitor)
    }

    /// 立即扫描（主窗口/菜单栏共用）。
    public func scanNow() async {
        await scanService.runScan(projectRoots: [])
    }

    /// 引导完成落盘 + 当次会话切回主界面。
    public func completeOnboarding() {
        firstRun.completeOnboarding()
        isOnboardingVisible = false
    }

    /// 设置页「重新显示引导页」：当次会话立即回到引导（落盘标记不变，完成后再消失）。
    public func requestOnboarding() {
        isOnboardingVisible = true
    }

    /// 合并 catalog + 禁用合成条目（标签筛选视图使用）。
    func catalogForTagFilter() -> [Skill] {
        catalogStore.current + tagService.disabledTaggedSkills(catalog: catalogStore.current)
    }

    /// 操作 + 历史落账。
    func runOperation(skill: Skill, direction: OperationDirection) async {
        await operationService.run(skill: skill, direction: direction)
        if let failure = store.state.operation.failureMessage {
            history.append(skillID: skill.id, name: skill.name, direction: direction, result: .failure(message: failure))
        } else {
            history.append(skillID: skill.id, name: skill.name, direction: direction, result: .success)
        }
        // 停用/删入回收站会搬移区内容——目录区计数失效（下一帧重枚举）
        bumpZones()
    }

    /// 停用区恢复（区行入口：zone 条目不在 catalog，直接走 lifecycle；冲突明细走操作状态机）。
    public func enableFromZone(zone: LifecycleZone, row: ZoneRowModel) async {
        let lifecycle = self.lifecycle
        let direction: OperationDirection = zone == .disabled ? .enable : .snapshotRestore
        await store.dispatch(.operationStarted(skillID: row.id, direction: direction))
        do {
            switch zone {
            case .disabled:
                _ = try lifecycle.enable(agentID: row.agentID, name: row.name)
            case .trash:
                _ = try lifecycle.restoreFromTrash(agentID: row.agentID, name: row.name)
            }
            await store.dispatch(.operationCompleted(skillID: row.id, direction: direction))
            history.append(
                skillID: row.originalPath, name: row.name, direction: .enable, result: .success
            )
        } catch {
            await store.dispatch(.operationFailed(
                skillID: row.id,
                direction: direction,
                message: "\(error)"
            ))
            history.append(
                skillID: row.originalPath, name: row.name, direction: .enable,
                result: .failure(message: "\(error)")
            )
        }
        bumpZones()
        await scanService.runScan(projectRoots: [])
    }

    /// 彻底删除单个回收站条目（不可恢复——UI 层负责确认弹窗）。
    public func purgeTrashEntry(_ row: ZoneRowModel) async {
        let lifecycle = self.lifecycle
        await store.dispatch(.operationStarted(skillID: row.id, direction: .delete))
        do {
            _ = try lifecycle.purgeTrash(agentID: row.agentID, name: row.name)
            await store.dispatch(.operationCompleted(skillID: row.id, direction: .delete))
            history.append(
                skillID: row.originalPath, name: row.name, direction: .delete, result: .success
            )
        } catch {
            await store.dispatch(.operationFailed(
                skillID: row.id,
                direction: .delete,
                message: "\(error)"
            ))
            history.append(
                skillID: row.originalPath, name: row.name, direction: .delete,
                result: .failure(message: "\(error)")
            )
        }
        bumpZones()
    }

    /// 清空回收站（不可恢复——UI 层负责确认弹窗）。
    public func purgeAllTrash() async {
        let lifecycle = self.lifecycle
        let count = (try? lifecycle.purgeAllTrash()) ?? 0
        if count > 0 {
            history.append(
                skillID: "trash", name: "清空回收站", direction: .delete,
                result: .success
            )
        }
        bumpZones()
    }

    /// 快照恢复（先快照当前 → 重建旧内容；失败回滚不丢数据）。
    func restoreSnapshot(skill: Skill, sha: String) async {
        await snapshotService.restore(skill: skill, sha: sha)
    }

    // MARK: - Phase 2：分发门面

    /// 把本机 skill 安装到目标 agent 的 skill 根目录（非破坏复制）。
    func distributeInstall(skill: Skill, targetSkillRoot: URL) async {
        await distributionService.install(
            source: .existingSkill(
                agentID: skill.owners.first ?? "unknown",
                name: skill.name,
                directoryPath: skill.directory.standardizedFileURL.path
            ),
            targetSkillRoot: targetSkillRoot,
            displaySkillID: "distribute|\(skill.name)",
            displayName: skill.name
        )
    }

    /// 导入本地目录到目标 agent 的 skill 根目录。
    func importSkill(from directory: URL, targetSkillRoot: URL) async {
        await distributionService.install(
            source: .localDirectory(path: directory.path),
            targetSkillRoot: targetSkillRoot,
            displaySkillID: "import|\(directory.lastPathComponent)",
            displayName: directory.lastPathComponent
        )
    }

    /// git 来源候选提案（clone 到临时区并列出合法 skill；零候选返回空数组）。
    /// 失败时走 store 的标准错误呈现（不进入 inFlight 状态机——提案阶段）。
    func proposeGitCandidates(url: String) async -> [GitSkillCandidate] {
        let installer = GitInstaller(baseDirectory: akBase)
        do {
            let materialized = try await installer.materialize(url: url)
            let candidates = installer.candidates(for: url, in: materialized)
            if candidates.isEmpty {
                await store.dispatch(.operationFailed(
                    skillID: "git-proposal",
                    direction: .distribute,
                    message: DistributionService.friendly(
                        .invalidSource(reason: "仓库中未发现合法 skill")
                    )
                ))
            }
            return candidates
        } catch {
            let message: String
            if let distributionError = error as? DistributionError {
                message = DistributionService.friendly(distributionError)
            } else {
                message = "\(error)"
            }
            await store.dispatch(.operationFailed(
                skillID: "git-proposal", direction: .distribute, message: message
            ))
            return []
        }
    }

    /// 勾选的 git 候选逐个安装（串行门内执行），装完清理临时区。
    func installGitCandidates(_ candidates: [GitSkillCandidate], targetSkillRoot: URL) async {
        let installer = GitInstaller(baseDirectory: akBase)
        for candidate in candidates {
            await distributionService.install(
                source: .localDirectory(path: candidate.directory.path),
                targetSkillRoot: targetSkillRoot,
                displaySkillID: "git|\(candidate.name)",
                displayName: candidate.name
            )
        }
        for candidate in candidates {
            installer.cleanup(candidate.directory)
        }
    }

    /// 更新全部铺设落点（确认后调用）。
    func updateAllLandingPoints(from skill: Skill) async -> LandingPointsUpdateSummary {
        await distributionService.updateAllLandingPoints(from: skill)
    }

    /// 把任意 skill 安装到目标 agent 的 skill 根目录（非破坏复制）的状态机入口由 install 承担；
    /// git 候选提案失败的错误呈现直接走 store（不进入 inFlight 状态机）。
    /// skillID → 标签名集合（按 TagStore.revision 缓存；曾每次 filter 调用重建整表、
    /// 逐 skillID N 次串行队列锁往返）。
    func tagsBySkill() -> [String: [String]] {
        let revision = tagService.storeRevision()
        if let cache = tagsSnapshot, cache.revision == revision {
            return cache.map
        }
        let map = tagService.assignedTagsBySkill()
        tagsSnapshot = (revision: revision, map: map)
        return map
    }

    private var tagsSnapshot: (revision: Int, map: [String: [String]])?

    /// 侧栏 agent 行模型（catalog version + agent 数 键控 memoize）——
    /// @ObservationIgnored：缓存本身不进 observable 通道，避免 getter 写缓存引发再渲染循环。
    @ObservationIgnored private var sidebarCache: (version: Int, agentCount: Int, rows: [SidebarAgentModel.Row])?

    func sidebarRows() -> [SidebarAgentModel.Row] {
        let version = catalogStore.version
        let agentCount = store.state.agents.count
        if let cache = sidebarCache, cache.version == version, cache.agentCount == agentCount {
            return cache.rows
        }
        let rows = SidebarAgentModel.build(agents: store.state.agents, skills: catalogStore.current)
        sidebarCache = (version, agentCount, rows)
        return rows
    }

    /// 总览仪表盘模型（catalog version + agent 数 + tag revision + 最近扫描时刻 键控 memoize）。
    @ObservationIgnored private var overviewCache: (key: OverviewCacheKey, model: OverviewModel)?

    struct OverviewCacheKey: Equatable {
        let catalogVersion: Int
        let agentCount: Int
        let lastScanAt: TimeInterval?
        let tagRevision: Int
    }

    func overviewModel() -> OverviewModel {
        let key = OverviewCacheKey(
            catalogVersion: catalogStore.version,
            agentCount: store.state.agents.count,
            lastScanAt: store.state.scan.lastCompletedAt?.timeIntervalSince1970,
            tagRevision: tagService.storeRevision()
        )
        if let cache = overviewCache, cache.key == key {
            return cache.model
        }
        let model = OverviewModel.build(
            state: store.state,
            skills: catalogStore.current,
            tagCount: tagService.tags().count
        )
        overviewCache = (key, model)
        return model
    }

    /// Reduce Motion 策略：用户设置覆盖优先，未覆盖时跟随系统辅助功能设置。
    var motionPolicy: MotionPolicy {
        MotionPolicy(reduceMotion: settings.effectiveReduceMotion(
            accessibility: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ))
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


