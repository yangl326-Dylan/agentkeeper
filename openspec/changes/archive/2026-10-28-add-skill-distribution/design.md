# Design

## Context

MVP（`add-scan-manage-mvp`，已归档）已交付：adapter 扫描体系、SKILL.md 解析与指纹、SQLite 索引 + FSEvents 增量刷新、禁用/启用的原子搬移（AtomicMover + manifest）、快照引擎与 git 历史、三面板 UI 与菜单栏。本 change 是 Phase 2 第一片：补齐 skill 的**分发**（跨 agent 安装、本地导入、git 来源安装）与**自定义标签**。全部工作在既有分层（DomainKit → InfraKit → AppCore → AgentKeeper）内增量，不改 Package 布局、不引入新第三方依赖（git 走 CLI）。

## Goals / Non-Goals

**Goals**:
- 一套 SkillDistributor 服务覆盖三种来源（本机 skill、本地目录、git 仓库）→ 统一安装管线（校验 → 冲突检查 → 原子落位 → 编目）
- 铺设分歧可视化：同名多落点指纹不一致时给出「以某版本更新全部落点」动作
- 标签存储独立于文件系统，禁用/重扫/恢复周期内不丢失
- 分发与标签变更纳入 OperationService 状态机与操作历史

**Non-Goals**:
- 社区 marketplace、在线目录 —— 后续 change
- 风险/安全扫描 —— 后续 change
- skill 编辑器、SKILL.md 修改 —— 后续 change
- 跨设备同步（iCloud/云）—— 后续 change
- 双向实时同步（改一处自动镜像他处）—— 本 change 只提供显式「更新所有落点」动作

## Decisions

### D1. 统一安装管线：三种来源收敛为一个 SkillDistributor
`SkillDistributor.install(source: .existingSkill(id:) | .localDirectory(URL) | .git(GitSourceSKill, selected), target: (agent, skillRoot))`：
1. **物化**：existing 直接用源目录；localDirectory 校验存在即用；git 先 clone 到 `~/.agentkeeper/tmp/clone-<uuid>/`（`git clone --depth 1 <url>`，本地路径直接用不用 clone），扫描出候选 skill 列表。
2. **校验**：逐候选跑既有 SkillParsing 规则（SKILL.md + 合法 frontmatter），非法即报缺失项，拒绝安装。
3. **冲突检查**：目标 `<skillRoot>/<skillName>` 已存在 → 指纹对比：一致则报告「已铺设」跳过；不一致则中止返回冲突明细，MUST NOT 覆盖。
4. **落位**：同卷 rename / 跨卷 copy+verify（复用 AtomicMover），目标是复制语义——用 copy+verify 亦可，统一走 AtomicMover 的复制路径（保留源，可回滚）。
5. **收尾**：删除临时 clone（`DeletionGate` 之外的内部临时区，直接 rm 即可，因为它不是用户数据）；记录 OperationHistory；触发重扫描。

**备选**：每来源一个独立 service。放弃原因：校验/冲突/落位逻辑完全同构，三实现必然漂移。

### D2. 铺设落点索引与「更新所有落点」
铺设识别已由 CatalogBuilder 的 multiAgent 重label提供；本 change 增补：按「同名 + 指纹分组」计算落点集合（provider 放在 CatalogQuery，复用 `owners` 扩展思路）。当组内指纹分歧：
- 每条落点记录标「已分歧」；
- 详情提供 `updateAllLandingPoints(from:)`：以选定版本为基准，对其余落点逐个「先快照当前 → 覆盖文件（copy+verify）→ 重扫」。覆盖是唯一允许写入既有落点的动作， MUST 先有自动快照兜底，且失败时逐落点回滚。落点上若已被禁用（在 disabled 区），跳过并列出，不接触 disabled 区。

**备选**：真·双向自动同步（文件事件驱动镜像）。放弃原因：与「文件系统唯一真相 + 显式操作」的既有心智冲突，自动写用户的 agent 目录风险高；xp 评估后仍可在此管线之上加。

### D3. git 来源约定
`git clone --depth 1` 处理 HTTPS/SSH 形式；`file://` 或裸路径直接复用为只读源目录（不 copy 到临时区，校验后直接从该路径安装）。候选发现：仓库根本身合法 → 单候选；否则取一级子目录逐个校验，多候选交 UI 勾选。clone 超时 60s，失败清空 `~/.agentkeeper/tmp/clone-<uuid>/` 整目录。不解析 SSH key、不管理凭据——失败时把 git stderr 摘要透传给用户。

**备选**：libgit2 / swift-git。放弃原因：MVP 已决策 CLI 封装，维持一致；GitService 已有版本嗅探基础设施。

### D4. 标签存储：独立 JSON + skillID 关联
`~/.agentkeeper/tags.json`：`{ "tags": ["写作", "实验"], "assignments": { "<skillRecencyPathHash>": ["写作"] } }`。key 用 skill 的稳定指纹路径（复用 SkillID 生成规则，MVP 已有：sha256 of skill 标识），保证路径搬迁（禁用/启用）后关联保留。
- 读写全内存 + 原子写（临时文件 + rename），损坏时备份损坏文件为 `tags.json.corrupt-<ts>` 并空库自愈（复用 SkillIndex 损坏自愈策略的轻量版）。
- 「已消失」清理：TagService 在重扫钩子后对照 catalog，把指向不存在（也非 disabled）skillID 的 assignment 转入 `orphanCount`，UI 提示并可一键清除。
- **不用 SQLite**：标签数据量极小，JSON 足够，且独立文件方便用户备份/手改。
- 禁用期间关联保留的依据：skillID 在禁用区不变（MVP 已保证）。

### D5. UI 集成点
- 详情页右侧操作区新增「安装到其他 agent…」（对已启用 skill）→ agent/skillRoot 选择弹窗 → 确认安装。
- 工具栏/菜单新增「导入 skill…」（本地目录）/「从 git 安装…」（URL 输入 + 多候选勾选面板）。
- 详情页标签编辑行（chips + 输入补全）；导航树新增「标签」分组（按标签名子分组）；筛选器增加标签维度。
- 铺设记录详情显示落点清单 + 分歧状态 + 「以此版本更新所有落点…」（确认框列明将写的落点）。
- 全部新操作走既有 StatusSemantics/MotionPolicy/RemediationPresentation 呈现失败与冲突。

### D6. 并发与状态机接入
安装/导入/clone 属于「写操作长任务」：DispatchQueue 的 serial worker 串行执行保证同一时刻最多一个分发操作；接入 OperationService 既有 `started → completed(自动重扫) / failed(不重扫)` 状态机，快照/铺设更新操作同样如此。UI 端 ChangePipeline 不感知新类型——重扫统一由 OperationService 完成钩子触发。

## Risks / Trade-offs

- **`git clone --depth 1` 对超大仓库仍有风险** → 60s 超时 + 明确报错，用户可用本地路径形式绕过；Phase 后续再考虑 mirror/ sparse-checkout。
- **tags.json 与 catalog 双源** → orphan 机制 + 单一写入口 TagService 封装，TDD 覆盖悬挂场景。
- **「更新所有落点」写入用户目录** → 三重保护：确认框列明落点、每落点先快照、失败逐落点回滚。

## Migration Plan

无既有数据迁移：新增 `~/.agentkeeper/tags.json`（首次为空）与 `~/.agentkeeper/tmp/`。旧 skills.db 不改 schema。回滚 = 删除新增文件，应用回到 MVP 行为。
