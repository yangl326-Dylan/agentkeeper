# 状态栏 agent 行 → 主窗口筛选设计

日期：2026-11-08
状态：已确认

## 背景

状态栏菜单里每个已安装 agent 目前点击后是「在 Finder 中打开 skills 目录」。用户更常见的动作是：看到某个 agent 的 skill 数，想直接进主窗口看它到底有哪些 skill。现在需要先打开主窗口，再手动点侧栏 agent，多一步。

目标：点击状态栏的 agent 行 → 主窗口前置，并只显示该 agent 的 skill。

## 行为

### 左键点击 agent 行

1. 激活 App
2. 打开或复用主窗口（`openWindow(id: "main")`）
3. 侧栏选中该 agent（`selectedNode = .agent(id)`）
4. 清空列表选中态
5. 清空主窗口搜索框

### 右键点击 agent 行

- 菜单项「在 Finder 中显示」：打开该 agent 的 skills 根目录（保留原有能力）
- 无可用目录时该项禁用，但左键筛选仍可用

## 架构

### `AppEnvironment`

新增：

```swift
public private(set) var searchResetToken: Int = 0

public func openAgentFilter(_ agentID: AgentID) {
    selectedSkillID = nil
    selectedNode = .agent(agentID)
    searchResetToken &+= 1
}
```

- 导航语义收口在 AppEnvironment，View 只负责调用，便于单测
- token 每次调用都递增，即使重复点同一个 agent，也能让主窗口重新清空搜索
- `searchResetToken` 是 observable（不加 `@ObservationIgnored`），主窗口通过 `onChange` 响应

### `MenuBarAgentRow`

- 主点击改为调用 `onSelect`
- 新增右键菜单：`contextMenu { Button(showInFinder) ... }`
- 移除「无目录时整行 disabled」的逻辑；目录只影响 Finder 菜单项
- 保留 hover 高亮与 skill 数展示

### `MenuSummarySection`

```swift
MenuBarAgentRow(
    ...,
    onSelect: {
        env.openAgentFilter(entry.id)
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
)
```

### `SkillListView`

```swift
.onChange(of: env.searchResetToken) { _, _ in
    searchText = ""
}
```

窗口新建时 `searchText` 本来就是空，不需要额外处理。

### `L10n`

新增中英文：

- `menuShowInFinder`：在 Finder 中显示 / Show in Finder
- `menuFilterAgentHelp`：打开主窗口并只看该 agent / Open the main window filtered to this agent

## 测试

| 测试 | 覆盖 |
|---|---|
| `openAgentFilterSetsAgentNode` | 节点变为 `.agent(id)`，`selectedSkillID` 清空 |
| `openAgentFilterClearsSearchEachTime` | 连续调用两次，`searchResetToken` 各递增一次 |
| `menuStringsLocalized` | 新增文案双语非空且中英不同 |
| `ProbeMenuBar` | 更新 `MenuBarAgentRow` 构造参数，仍能渲染出像素 |

## 非目标

- 不新建多个窗口
- 不改变侧栏点击行为
- 不自动触发扫描
- 不做 URL scheme / 深链
- 不改变菜单栏摘要的统计口径
