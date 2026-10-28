# Proposal

## Why

MVP 已交付单 agent 视角的管理能力（扫描、禁用/启用、快照），但用户在多个 agent 间复用 skill 仍需手动复制目录：没有跨 agent 分发入口、没有从外部来源（本地目录 / git 仓库）获取 skill 的途径，也无法用自定义标签组织个人工作流。这三项是 deferred 清单中依赖最少、价值最高的一片，现在补齐它们能直接把 AgentKeeper 从「查看器」升级为「分发中枢」。

## What Changes

- 新增**跨 agent 安装/同步**：从现有 skill 或外部来源将 skill 安装到指定 agent 的 skill 目录；同名复制到多个 agent 即生成 `multi-agent 铺设` 记录（与既有 skill-catalog 作用域语义衔接）；目标冲突时中止并展示冲突明细，MUST NOT 覆盖。
- 新增**本地导入**：把用户选择的任一本地目录（含合法 SKILL.md）作为 skill 导入指定 agent；非破坏性（复制而非搬移）。
- 新增 **git 来源安装**：输入 git URL（含本地路径形式），系统 clone 到临时区并校验 skill 内容后安装；clone 失败时清理并如实报错。
- 新增**自定义标签**：用户可为本机 skill 打任意自定义标签，用于导航分组与筛选；标签随索引缓存持久化，重扫不丢失。
- 分发/导入操作纳入既有 OperationService 状态机（成功自动重扫、失败不重扫）与操作历史审计。

## Capabilities

### New Capabilities

- `skill-distribution`：跨 agent 安装/同步、multi-agent 铺设生成、本地导入与 git 来源安装的来源→目标分发行为及冲突保护。
- `skill-tags`：用户自定义标签的增删、随 skill 持久化、导航分组与筛选集成。

### Modified Capabilities

<!-- 本 change 不修改既有 capability 的 requirement：铺设语义已在 skill-catalog 定义，分发是新增输入路径；标签筛选复用统一查询视图既有 requirement，无需改动其文本。 -->

## Impact

- `Sources/InfraKit`：新增 SkillDistributor（安装/导入/clone 校验，复用 Fingerprint + AtomicMover 安全策略）、TagStore（`~/.agentkeeper/tags.json`，含损坏自愈）。
- `Sources/AppCore`：新 DistributionService/TagService action 层，接入 OperationService 状态机；CatalogQuery 增加标签筛选维度（不改对外 requirement 语义）。
- `Sources/AgentKeeper`：详情页「安装到其他 agent」入口、导入/git 安装对话框、标签编辑与筛选 UI。
- 无数据库 schema 变更（标签独立 JSON 存储）；不引入网络 SDK（git 通过 `git` CLI）。
