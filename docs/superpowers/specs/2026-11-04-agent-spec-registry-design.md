# Agent 扩展设计：单源 AgentSpec 注册表 + 用户自定义 agent

日期：2026-11-04
状态：已批准（用户选择 A + B）

## 背景

新增一个 agent 当前需要改 6 处，其中 3 处是「不写不报错、但功能残缺」的隐藏点：

| 位置 | 作用 | 不写的后果 |
|---|---|---|
| `StandardAgentAdapter` 工厂 | 检测路径 / skill 根 | agent 不被识别 |
| `NamedAdapters` | 具名类型 | 编译期 API 缺失 |
| `AgentRegistry.init` | 注册 | 不参与扫描 |
| `ProjectScope.AgentProjectLayout` | 项目级目录约定 | 项目内 skill 扫不到 |
| `MenuBarIcons` | 图标 | 回落 terminal（无害） |
| `SkillLifecycle.knownAgentIDs` | 生命周期区枚举 | **停用/回收站条目不可见** |

且 `knownAgentIDs` 默认值已漏掉 `qwen` / `cursor` / `agents-shared`，这三个 agent 的停用条目在 UI 与 `ak disabled` 中查不到——现存 bug。

目标：

1. 把「一个 agent 的全部知识」收敛为单一结构体 `AgentSpec`，其余全部派生。
2. 生命周期区改为目录枚举，不再依赖任何名单（根治上述 bug，并让自定义 agent 自动可用）。
3. 支持 `~/.agentkeeper/agents.json` 用户自定义 agent，无需重新编译。

## 方案

### 1. AgentSpec（`Sources/InfraKit/AgentSpec.swift`）

```swift
public struct AgentSpec: Sendable, Hashable {
    public var id: AgentID                 // kebab-case，稳定标识
    public var displayName: String
    public var detectionSubpaths: [String] // 任一存在 → installed
    public var skillRootCandidates: [String]
    public var skillRootGlobs: [String]    // `*` 恰匹配一层（插件缓存）
    public var projectSkillSubpaths: [String]
    public var projectRootDiscovery: ProjectRootDiscovery
    public var icon: String                // SF Symbol，缺省 terminal
}
```

`BuiltInAgents` 以静态属性表达 10 个内置 agent，`all` 汇总；`spec(for:)` 查表。

派生关系：

- `AgentRegistry.init(homeDirectory:)` = 内置 specs + 用户 specs → `StandardAgentAdapter(spec:homeDirectory:)`
- `ProjectRootScanner(specs:)` 使用 registry 的 specs 枚举项目级 skill 根
- `MenuBarIcons.icon(for:)` 查 spec.icon，未知回落 terminal
- `NamedAdapters` / `ClaudeCodeAdapter` 退化为委托壳（保持公开 API 兼容）
- `StandardAgentAdapter` 的 9 个工厂方法删除（配置改由 spec 承载）

### 2. 生命周期区改为目录枚举（`SkillLifecycle`）

`entries(zone:)` / `unknownDisabledEntries()` / `cleanupOrphanManifests()` 不再遍历
`knownAgentIDs`，而是枚举 `<base>/disabled/*`、`<base>/trash/*` 下的 agent 目录。

- 任何 agent（内置/自定义/已卸载）留下的条目都能被看到
- `knownAgentIDs` 参数保留（并集兜底），默认空
- manifest 仍按 `<agent>/<name>.manifest.json` 定位，格式不变

### 3. 用户自定义 agent（`~/.agentkeeper/agents.json`）

```json
{
  "agents": [{
    "id": "windsurf",
    "displayName": "Windsurf",
    "detectionSubpaths": [".windsurf"],
    "skillRootCandidates": [".windsurf/skills"],
    "projectSkillSubpaths": [".windsurf/skills"],
    "icon": "wind"
  }]
}
```

校验规则（宁严勿松）：

- `id` 必须匹配 `^[a-z0-9][a-z0-9-]*$`
- 与内置 id 冲突 → 忽略该条（内置优先，防劫持）
- 重复 id → 先出现者生效
- 所有路径必须相对家目录；拒绝绝对路径、`~`、`.`、`..`
- `detectionSubpaths` 不得为空
- `projectRootDiscovery` 仅支持 `"none"`（自定义项目根发现留待后续）
- 文件缺失 → 静默空结果；JSON 损坏 / 条目非法 → `ScanDiagnostic(.unrecognizedStructure)`，不阻塞扫描
- 生效时机：下次扫描（每次扫描重建 registry，无需文件监听）

## 非目标（YAGNI）

- 动态库插件加载
- UI 内编辑 agents.json（手写文件即可）
- 热重载（改文件后下次扫描生效）
- 自定义项目根发现策略
- 自定义 agent 的菜单栏图标之外的外观定制

## 测试

| 套件 | 覆盖 |
|---|---|
| `AgentSpecTests` | 10 内置 id 唯一；claude-code 项目根策略；opencode globs；项目布局派生与旧行为一致 |
| `UserAgentConfigTests` | 合法生效；内置冲突/绝对路径/`..`/坏 JSON/重复 id |
| `SkillLifecycleZoneTests` | 不传 knownAgentIDs 也能枚举 qwen / 自定义 agent 条目 |
| `MenuBarIconsTests` | 图标派生 + 未知回落 + 自定义 agent 图标 |
| `AgentRegistryE2ETests` | fake home + agents.json → 扫描出 agent 与 skill |

## 验收

`swift build` 0 warning；全量 suite 全绿；真实机器 `ak doctor` 行为零回归；文档 `docs/adding-an-agent.md` + README 补 `agents.json`。
