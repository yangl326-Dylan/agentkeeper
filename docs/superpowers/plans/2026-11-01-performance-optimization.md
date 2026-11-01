# 性能优化实施计划（P0+P1，2026-11-01 review 后续）

> 执行模式：inline（本 session），每簇全量回归（279 tests）+ 0-warning 后提交。
> 来源：docs/superpowers/specs/2026-11-01-performance-review（三路并行审计结论）。

## 决策记录

- **不动 AppStore 单属性架构**（P0-4 缓解方案改为事件整批聚合 + 读取面缓存收敛）：拆域是 279 个测试的面级重构，风险/收益比差；事件聚合把 dispatch 风暴的基数砍掉后，粗粒度失效的实际损失最小化。P0-4 记为完成（以缓解手段达成），后续认为必要时再拆。

## Task 簇 A（quick wins：BMI 最大）

1. **详情面板去 body 内 SHA256**（RootView landingPointsSection）：用 catalog 同名 skill 的 `sha256` 建 `[path:sha]` 映射比对，删两处 `Fingerprint.sha256OfDirectory`。零 IO。
2. **ChangePipeline.rescanNow 去二次 build+sync**：只留 `runScan`（runner 内已 build+sync）。
3. **筛选管线瘦身**：SkillListView body 算一次 query 传给 SkillListCore + animation value 复用；`selectedTag == nil` 时跳过 `tagsBySkill()`；TagStore 加 `revision` + 单锁 `assignedTagsBySkill()` 快照；AppEnvironment memoize。
4. **DateFormatter static 化**：RateStatusText.compact / OverviewDashboard.clockText。
5. **P2 顺手**：FSEventMonitor stop release Unmanaged；AppEnvironment FirstRunStore 合一。

## Task 簇 B（P0 工程项）

6. **Fingerprint 单 pass 流式哈希 + stat 缓存**（path+mtime+size → sha，进程级共享缓存）；parseDirectory/CatalogBuilder 透传。`parseDirectory` 枚举顺带带出 mtime（删第三遍 pass）。
7. **SnapshotService.autoSnapshot 移后台**（Task.detached，与 restore 同法）。
8. **SkillIndex**：prepared statement 复用 + 单 JSONEncoder + step 返回码检查 + `replace(_:)` 异步写（queue.async，不阻塞 MainActor）；CatalogStore.sync 改用异步 replace，`current` 更新仍在主线程。
9. **ScanService 并发重入门禁**（inFlight guard）。
10. **自反馈扫描过滤**：ChangePipeline.onEvents 丢 `.ak-stage-`/`.ak-old-`/`.keeper-backup-` 前缀事件。

## Task 簇 C（P1 剩余）

11. **FSEvent 整批聚合**：FSEventMonitor handler 改 `(paths: [String]) async -> Void`（单批一次 Task）；ChangePipeline.onEvents(paths:) 一次 dispatch + 一次 debounce 重挂；onEvent(rootPath:) 保留为兼容单参。
12. **URL 预览**（详情 history/snapshots 异步化）：SkillDetailContent @State + `.task(id: skill.id)`（detached 读盘）。
13. **Markdown 单次解析 + LazyVStack**：@State 缓存 blocks（task(id: markdown) detached 解析）。
14. **启动异步缓存加载**：CatalogStore init `loadCacheEagerly` 参数（默认 true 兼容既有测试），AppEnvironment 传 false + bootstrap 后台 all() 回填。
15. **禁用路径 sha 单次计算**：AtomicMover.planMove 增 `expectedSha256` 可选参数，SkillLifecycle 传入。
16. **侧栏/Overview version-keyed 缓存**：CatalogStore 增 `version`；NavigationSidebar/OverviewDashboard @State 缓存派生数据。

## 回归纪律

每簇：`swift build` 0-warning → `swift test` 全绿 → `git commit`。UI 相关改 ProbeMenuBar/UI 探针仍在跑。
