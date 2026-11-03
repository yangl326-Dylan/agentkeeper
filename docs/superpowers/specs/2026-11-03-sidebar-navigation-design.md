# 侧栏导航视图设计（单选互斥 + 组合过滤收敛）

日期：2026-11-03
状态：已确认（用户选定：导航视图 / 移除工具条菜单 / 显式「所有 Skills」节点）

## 背景与问题

三面板主壳的过滤状态目前分散在三处，语义互相打架：

| 入口 | 交互语义 | 状态 |
|------|----------|------|
| 侧栏 Agents 区 | 点击 toggle（单选，再点取消） | `selectedAgent: AgentID?` |
| 侧栏 作用域/标签区 | 点同节取消、点异节切换（实际单选） | `selectedScopes: Set<ScopeKind>` |
| 侧栏 生命周期区 | 选中时**静默清空** agent/scope 筛选 | `selectedZone` |
| 工具条「筛选」菜单 | 4 个 Toggle **多选** | 同一个 `selectedScopes` |

核心矛盾：侧栏作用域节点与工具条菜单操作同一状态但语义不同（单选 vs 多选）；生命周期互斥是用户不可见的隐式规则；`AgentSelection` / `SectionSelection` 两个 toggle 工具类支撑着一套无人能完整说清的组合规则。

用户决策（2026-11-03 确认）：

1. **侧栏定位 = 导航视图**：单选，某一时刻只看一个视角；不做多维过滤器面板。
2. **工具条 scope 多选菜单移除**，当前视图以导航标题展示；搜索独立生效。
3. **显式「所有 Skills」根节点**，启动默认选中；选中态永远有落点。

## 信息架构（侧栏）

```
所有 Skills            ← 新增常驻根节点，启动默认选中（count = catalog 总数）
─────
Agents                ← 已安装 agent 一行一个，单选
作用域
  全局 (N)            ← global + multiAgent
  项目级
    ├ <项目名> (N)    ← 按项目名分组（现状不变）
标签
  <标签名> (N) …
生命周期
  禁用区 (N)
  废纸篓 (N)
```

- 全侧栏**同一时刻只有一个选中节点**；所有区块从 Button+checkmark 改为原生 `List(selection:)` 单选高亮（与 Finder/Mail 心智一致）。
- 删除全部隐式规则：「点同项取消」「生命周期清空其它筛选」不再存在——想回去点「所有 Skills」。

## 组合语义（唯一规则）

```
当前视图 = 侧栏选中节点（静态集合）
列表 = 视图 ∩ 搜索词        ← 唯一的叠加维度
```

- 搜索框独立生效，AND 叠加；清空即回到节点全量。
- **agent 专属 skill 只能从 Agents 区进入**（「全局」节点不含 agentOnly——沿用现状，工具条菜单移除后这是预期行为而非功能丢失）。
- 侧栏 count 为静态编目数，不随搜索词变化。
- 切换视图时，详情面板选中的 skill 若不在新视图内则清空 `selectedSkillID`。

## 列表区展示

- 工具条删除「筛选」菜单，「立即扫描」保留。
- 导航标题反映当前视图：`Skills`（所有）/ `Skills · 全局` / `Skills · claude-code` / `Skills · <项目名>` / `Skills · #<标签>` / `禁用区` / `废纸篓`。
- 不加顶部 chips——标题已表达视图，避免重复展示。

## 状态与实现落点

- `AppEnvironment.selectedAgent / selectedScopes / selectedZone` 收敛为单一 `selectedNode: SidebarNode`：

```swift
enum SidebarNode: Hashable {
    case all
    case agent(AgentID)
    case global                       // 全局（global + multiAgent）
    case project(String)              // 项目名
    case tag(String)
    case zone(LifecycleZone)
}
```

- 删除 `SectionSelection` / `AgentSelection` 工具类。
- **视图 → 查询映射为纯函数** `NavigationModel.query(for:node:) -> CatalogQuery`（放 AppCore，可单测）；`SkillListCore.filter` 保持现有 memoize 性能路径，输入从三状态变一状态。
- 侧栏行模型（`sidebarRows` 等 memoize）按新单选模型适配。

## 错误处理

- 节点背后的集合为空（如标签被全部移除、agent 被卸载）：节点从侧栏消失时若正被选中，回落到 `.all`。
- 扫描重建 catalog 期间保持当前节点选中（按节点标识匹配，不按 index）。

## 测试

- AppCore 单测：`SidebarNode → CatalogQuery` 映射（各节点类型、agentOnly 归属、空 catalog、节点失效回落 `.all`）。
- 现有 NavigationModel / Reducer / 探针测试相应迁移；TDD RED→GREEN。
- 纪律：`swift build` 0-warning；全量 suite 全绿后提交（GitInstaller 在途测试失败不在本设计范围）。

## 不做（YAGNI）

- 多 agent 对比 / scope 多选组合（导航视图语义下有意去掉；搜索 + 标签覆盖临时组合需求）。
- 侧栏 count 随搜索词联动。
- ⌘K / Quick Look 跳转（roadmap 既有项，不在本次）。
