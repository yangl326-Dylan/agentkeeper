# Design

## Context

AgentKeeper 是全新 macOS 原生 Swift 应用（greenfield）。目标:高稳定性、高质量 UI 与动效。技术栈基底在头脑风暴中已与用户确认:

- **形态**:主窗口 + 菜单栏常驻（两者都要）
- **技术栈**:SwiftUI + AppKit 混合（SwiftUI 主体/动效，AppKit 桥接 diff/复杂控件），macOS 14+
- **架构取向**:文件系统为唯一真相 + SQLite 索引缓存（Approach C）
- **动效参考**:Xcode 三面板骨架 + Things 3 动效品位 + CleanMyMac 的风险视觉语义

本变更只覆盖 MVP（扫描 + 查看 + 管理 + 快照历史），同步/安装、风险扫描、编辑器为后续独立 change。

## Goals / Non-Goals

**Goals**:
- 建立分层架构与消息流骨架，后续所有 change 都在此骨架上增量
- 扫描器可插拔（adapter 注册表），数据模型可容纳未来同步/风险扫描字段
- 文件操作零损：原子、可回滚、可审计
- UI 响应实时性：FSEvents 驱动增量刷新

**Non-Goals**:
- 跨 agent 同步、安装（git/市场/本地导入）——后续 change
- SKILL.md 编辑器——后续 change
- 风险扫描引擎——后续 change（但数据模型预留 `origin`/`riskSummary` 字段）
- libgit2 / 沙盒化（MVP 决策见下）

## Decisions

### D1. 分层架构与单向数据流
**结构**（模块目标为 Swift Package 产出静态库或多 target）：`AgentKeeper`（Presentation: SwiftUI 视图/动效）→ `AppCore`（AppState reducer、命令、UI 状态机、快照编排）→ `DomainKit`（Agent/Skill/SkillStatus/ScanReport 模型与协议）→ `InfraKit`（AgentScanner/ adapters、SkillIndex SQLite、FileMonitor FSEvents、SnapshotStore、GitService）。

Presentation 只订阅 `AppUpdate` 消息流渲染，不直接触碰 InfraKit——保证 UI 不出新状态、InfraKit 可独立单测。
**备选**:MVVM 直连模型。放弃原因：视图直连让扫描/监控这类后台竞态直接泄漏进 UI 层，稳定性风险大。

### D2. 文件系统唯一真相 + SQLite 索引
SkillIndex（SQLite）只缓存解析结果与指纹，一切状态以磁盘为准。启动做增量扫描（对比 mtime+指纹），运行期由 FSEvents 驱动增量重扫。索引失真时以磁盘纠正并覆盖索引。
**备选**:数据库主档。放弃原因：用户在终端改动是常态，双源冲突是维护噩梦。
**UI 数据源**:AppCore 在内存中维护只读 catalog 快照数组,UI 不直接读 SQLite——SwiftUI 侧只有纯状态。

### D3. 禁用区与 manifest
禁用=原子搬移到 `~/.agentkeeper/disabled/<agent>/<skill>/`，manifest JSON 记录 `{originalPath, disabledAt, sha256, files:[...]}`。搬移在同物理卷用 rename（原子）；跨卷先 copy+verify再删源。失败沿 manifest 反向回滚。冲突（原路径被占用）→ 中止 + UI 冲突面板，绝不覆盖。
**备选**:原地改名 `.disabled` 后缀。放弃原因:部分 agent 会扫码所有子目录，改名仍可能被误解析;统一禁用区还提供“回收站式”审查视图。

### D4. 快照引擎
SnapshotStore:每次指纹变化写 `~/.agentkeeper/snapshots/<skillId>/<sha256-or-timestamp>/`，manifest 含文件清单+hash。去重规则:同 skipExisting 指纹不重快照。恢复=先快照当前，再按 manifest 反向重建。保留上限:默认 50 份/skill，最旧淘汰，可在设置改。Git 历史通过 `GitService` 的 CLI 封装（`git log --follow -- path`、`git diff`），`--porcelain` 输出解析;非 git 目录隐藏该 UI 区块而不是置灰。

**备选**:SQLite blob 存快照内容。放弃原因:大文件 blob 性能差且不便于用户手动抢救文件;目录形态让快照可以「逃逸」（用户能自己从磁盘救文件）。

### D5. FSEvents 监听策略
FileMonitor 监听每个 agent 的 skill 根目录（不是每个 skill），事件聚合 debounce 500ms→增量重扫相关目录。应用失焦时降频（2s 合批）省电。
**备选**:轮询/mtime。放弃:FSEvents 是 macOS 原生机制,CPU 影响为纳秒级,轮询会有可感延迟。

### D6. Adapter 体系
`AgentAdapter` 协议:`detectInstallation() → AgentInstallState`、`skillRoots() → [SkillRoot]`、`parseSkill(at:) → ParsedSkill?`。每个 adapter 内部声明它支持的结构版本,未知结构返回 `.unrecognized(path)` 而非错误。Claude Code adapter 首期覆盖:用户级 `~/.claude/skills`、项目级扫描（via `~/.claude.json` 配置或用户选择的项目根）→ MVP 建议仅扫**用户级**,项目级列为 follow-up。
**理由**:项目级涉及其它任意目录的递归与授权,闪烁 scope 风险;MVP 聚焦用户级,同一 adapter 架构下后续加 root 即可。

### D7. UI 动效规范
- 三面板布局:`NavigationSplitView`（sidebar=agent 树,`List`=skill 列表,`Detail`=详情/文件）
- 动效:SwiftUI `withAnimation(.snappy)` / `spring(duration:)` 做列表过渡与面板展开;降级开关:尊重系统「减少动态效果」（reduce motion）与「减少透明度」辅助功能设置,触发时以即时切换替代装饰性动画
- 详情页 SKILL.md 渲染:初版用 `AttributedString` 轻量 markdown 渲染（不引第三方,保持稳定）;diff 视图用 AppKit `NSTextView` 桥接 + AttributedString 标色
- 状态语义:绿色=正常/启用,琥珀=待关注(变更/冲突), 灰=禁用, 红=需处理(权限/失败), 半透明=无法识别;遵循系统语义同时不打架
- 菜单栏:MenuBarExtra(.menuBarExtraStyle = .menu) 显示 agent 摘要与快捷操作

### D8. 分发与权限策略
MVP 目标为非沙盒 + Developer ID（本地/直接分发），避免 App Store 沙盒对 `~/.claude` 等目录的额外摩擦。之后如有上架需求再评估沙盒+security-scoped bookmarks 迁移成本。
**备选**:上架 App Store,放弃原因:沙盒与用户级 agent 目录读取组合会引入 Bookmarks 迁移复杂度,与 MVP 稳定性目标冲突。

### D9. 测试策略
- DomainKit/InfraKit 纯逻辑 100% 单测（XCTest），文件操作类测试在临时目录夹具（`FileManager.temporaryDirectory` 每用例新建）中真跑;FSEvents 测试用注入 FakeMonitor 协议
- UI/AppCore:ViewModel reducer 纯函数单测;快照/搬移路径用 fixture 驱动端到端集成测
- 手动验收清单:三个 agent 真实机器 + 干净机虚拟机各一轮

## Risks / Trade-offs

- [Agent 目录结构随版本漂移] → adapter 声明结构版本 + `.unrecognized` 降级;每次扫描报告开发者诊断信息（不弹 UI）
- [FSEvents 缺 coalescing,可能高频事件风暴] → debounce + per-root 节流,压测
- [禁用后 agent 自身工具更新可能误将 disabled 区视为 skill 源] → 禁用区路径固定在 `~/.agentkeeper`(非 agent 标准路径),并在文档明示
- [SQLite 索引损坏] → 索引可随时从磁盘全量重建（「fs is truth」设计的根本安全网）;启动时若 integrity check 失败自动 drop+rebuild
- [git CLI 输出格式跨版本差异] → 解析器加版本嗅探与 `--porcelain` 固定格式,单测覆盖 macOS 自带 git + brew git 两个版本
- [非沙盒渲染新签名/RIF 需求需用户理解] → README + 首启引导页说明

## Migration Plan

Greenfield,无数据迁移。首版发布前在真机完成:安装→首次扫描→禁用/启用→修改触发快照→恢复旧版本 的手工 E2E;`~/.agentkeeper` 目录结构首次即定型,后续扩展只加不拆。

## Open Questions

无阻塞性开放问题。以下为实施期可内决策项,不影响 spec/任务拆分:
- Swift Package 多 target vs Xcode target 分层的落地细节
- 菜单栏面板初版信息密度的具体字数与条目数
