# 接入一个新 agent

AgentKeeper 的 agent 知识只有一个真相：`AgentSpec`（`Sources/InfraKit/AgentSpec.swift`）。
注册表、项目级扫描、菜单栏图标、生命周期区全部由它派生，因此接入 agent 只有两条路：

| 场景 | 做法 | 需要重新编译/发版 |
|---|---|---|
| 内置 agent（主流工具） | 在 `BuiltInAgents` 加一个字面量 + 测试 | 是 |
| 长尾 / 私有 agent | 写 `~/.agentkeeper/agents.json` | 否 |

---

## 一、内置 agent（改代码）

### 1. 加一个 `AgentSpec` 字面量

编辑 `Sources/InfraKit/AgentSpec.swift`，在 `BuiltInAgents` 里加：

```swift
/// Foo（一句话说明目录约定）。
public static let foo = AgentSpec(
    id: "foo",                                  // kebab-case，稳定标识
    displayName: "Foo",
    detectionSubpaths: [".foo"],                // 任一存在 → 已安装
    skillRootCandidates: [".foo/skills"],        // 用户级 skill 根候选
    projectSkillSubpaths: [".foo/skills"],       // 项目根内的候选（不需要则省略）
    icon: "terminal"                             // 菜单栏 SF Symbol（省略即 terminal）
)
```

然后把 `foo` 加进 `BuiltInAgents.all`（顺序即侧栏顺序）。

字段说明：

| 字段 | 相对路径基准 | 说明 |
|---|---|---|
| `id` | — | 必须匹配 `^[a-z0-9][a-z0-9-]*$`；用于归属、禁用区目录名与 CLI 输出 |
| `displayName` | — | UI 显示名 |
| `detectionSubpaths` | 家目录 | 任一存在即 `installed`；存在但是文件 → `unrecognizedStructure` |
| `skillRootCandidates` | 家目录 | 仅报告实际存在的目录 |
| `skillRootGlobs` | 家目录 | `*` 恰匹配一层；用于 npm 插件缓存这类动态路径 |
| `projectSkillSubpaths` | 项目根 | 项目级扫描候选；空数组 = 不支持项目级 |
| `projectRootDiscovery` | — | 目前 `.none` 或 `.topLevelJSONProjects(jsonSubpath:)` |
| `icon` | — | SF Symbol；空串按 `terminal` 处理 |

**不要**再手工修改这些地方——它们已全部从 spec 派生：

- `AgentRegistry`（注册表）
- `AgentProjectLayout` / `ProjectRootScanner`（项目级扫描）
- `MenuBarIcons`（菜单栏图标）
- `SkillLifecycle`（停用区/回收站枚举，按目录发现，不依赖名单）

如需具名 adapter（客户端/测试用具体类型），在 `Sources/InfraKit/Adapters/NamedAdapters.swift`
照现有 10 行样板加一个委托壳即可；`AgentRegistry` 本身不需要改。

### 2. 加测试

`Tests/InfraKitTests/AgentSpecTests.swift` 里断言新 id 在 `BuiltInAgents.all` 中；行为测试照
`Tests/InfraKitTests/GeminiOpenClawAdapterTests.swift` 写 4 个用例（已安装 / 未安装 / skill 根存在 / 解析 SKILL.md），
fixture 用 `makeFakeHome(files:)`。

### 3. 验收

```bash
swift build   # 0 error 0 warning
swift test
```

---

## 二、用户自定义 agent（不改代码）

写 `~/.agentkeeper/agents.json`，下次扫描（或重启 App / 重跑 `ak doctor`）即生效：

```json
{
  "agents": [
    {
      "id": "windsurf",
      "displayName": "Windsurf",
      "detectionSubpaths": [".windsurf"],
      "skillRootCandidates": [".windsurf/skills"],
      "skillRootGlobs": [],
      "projectSkillSubpaths": [".windsurf/skills"],
      "icon": "wind"
    }
  ]
}
```

字段与内置 `AgentSpec` 一一对应，其中只有 `id`、`detectionSubpaths`、`skillRootCandidates` 必填。

### 校验规则（v1，宁严勿松）

| 规则 | 违反后果 |
|---|---|
| `id` 匹配 `^[a-z0-9][a-z0-9-]*$` | 该条目被忽略 |
| `id` 与内置 agent 冲突 | 该条目被忽略（内置优先，防劫持） |
| 重复 `id` | 先出现者生效，后者忽略 |
| `detectionSubpaths` 为空 | 该条目被忽略 |
| 路径含绝对路径 / `~` / `.` / `..` | 该条目被忽略 |
| `projectRootDiscovery` 非 `"none"` | 该条目被忽略（自定义项目根发现暂不支持） |

被忽略的条目**不会静默消失**：会产出一条 `ScanDiagnostic(kind: .unrecognizedStructure)`，
path 指向 `agents.json`，在 App 的诊断区与 `ak doctor` 里可见。文件不存在则视为没有自定义 agent。

### 生效范围

自定义 agent 与内置 agent 走同一条管线：侧栏、总览、菜单栏、`ak list` / `ak doctor`、
项目级扫描、停用/回收站都会自动包含它。

改完文件无需重启：每次扫描都会重新读取 `agents.json`。

---

## 三、常见坑

- **id 不是目录名**：禁用区按 `<base>/disabled/<id>/` 建目录，改 id 会让历史停用条目落到新目录（旧条目仍可见，但归属显示为旧 id）。
- **glob 只支持一层 `*`**：`a/*/b` 可以，`a/**/b` 不支持。
- **`detectionSubpaths` 决定「已安装」**：只有 skill 根存在但检测目录不存在时，agent 会显示为未安装（skill 仍可被扫描，但侧栏归属可能不符合预期）。
- **项目级目录需要项目根**：项目根来自 agent 自身记录（如 `~/.claude.json`）或用户在设置里手动添加；没有项目根就不会扫项目级目录。
