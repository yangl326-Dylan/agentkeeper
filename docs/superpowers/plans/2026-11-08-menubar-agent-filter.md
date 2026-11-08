# 状态栏 agent 行 → 主窗口筛选 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 点击状态栏菜单里的 agent 行时，打开/前置主窗口并只显示该 agent 的 skill，同时清空搜索框。

**Architecture:** 导航与搜索状态都收口到 `AppEnvironment.openAgentFilter(_:)`；View 负责 `activate` + `openWindow`。搜索词不再是列表局部状态，入口可直接清空。

**Tech Stack:** Swift 6 / SwiftUI / Swift Testing / macOS 15+

---

### Task 1: AppEnvironment 导航入口

**Files:**
- Modify: `Sources/AgentKeeperUI/AppEnvironment.swift:24-36`
- Test: `Tests/AgentKeeperTests/AgentFilterTests.swift`

- [ ] **Step 1: 写失败测试**

在 `AgentFilterTests` 末尾追加：

```swift
    /// 状态栏 agent 行：设置 agent 节点、清空选中与搜索词。
    @Test func openAgentFilterSetsAgentNodeAndClearsSearch() throws {
        let home = makeFakeHomeCore(files: ["d"])
        defer { try? FileManager.default.removeItem(at: home) }
        let env = AppEnvironment(homeDirectory: home)

        env.selectedSkillID = "any"
        env.searchText = "review"

        env.openAgentFilter("agent-0")
        #expect(env.selectedNode == .agent("agent-0"))
        #expect(env.selectedSkillID == nil)
        #expect(env.searchText.isEmpty)

        // 重复点同一个 agent 也要再次清空搜索
        env.selectedSkillID = "any"
        env.searchText = "plan"
        env.openAgentFilter("agent-0")
        #expect(env.selectedSkillID == nil)
        #expect(env.searchText.isEmpty)
    }
```

- [ ] **Step 2: 运行测试确认失败**

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null
swift test --filter AgentFilterTests 2>&1 | tail -12
```

Expected: 编译失败，`AppEnvironment` 没有 `searchText` / `openAgentFilter`。

- [ ] **Step 3: 实现**

在 `Sources/AgentKeeperUI/AppEnvironment.swift` 的 `selectedNode` 之后加入：

```swift
    /// 主窗口搜索词（单一数据源：状态栏切 agent 时可直接清空）。
    public var searchText: String = ""

    /// 状态栏 agent 行入口：切到该 agent 视图、清空选中与搜索。
    public func openAgentFilter(_ agentID: AgentID) {
        selectedSkillID = nil
        selectedNode = .agent(agentID)
        searchText = ""
    }
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter AgentFilterTests 2>&1 | tail -6
```

Expected: `Test run with N tests passed`。

- [ ] **Step 5: 提交**

```bash
git add Sources/AgentKeeperUI/AppEnvironment.swift Tests/AgentKeeperTests/AgentFilterTests.swift
git commit -m "feat(menubar): 增加 agent 筛选导航入口"
```

---

### Task 2: 菜单栏文案

**Files:**
- Modify: `Sources/AppCore/L10n.swift:255-263`
- Test: `Tests/AppCoreTests/L10nTests.swift`

- [ ] **Step 1: 写失败测试**

在 `L10nTests` 的 `updateStringsAreLocalized` 之后追加：

```swift
    /// 菜单栏 agent 行文案：双语非空且中英不同。
    @Test func menuAgentRowStringsAreLocalized() {
        let zh = L10n(lang: .zhHans)
        let en = L10n(lang: .english)
        #expect(!zh.menuShowInFinder.isEmpty)
        #expect(!en.menuShowInFinder.isEmpty)
        #expect(!zh.menuFilterAgentHelp.isEmpty)
        #expect(!en.menuFilterAgentHelp.isEmpty)
        #expect(zh.menuShowInFinder != en.menuShowInFinder)
        #expect(zh.menuFilterAgentHelp != en.menuFilterAgentHelp)
    }
```

- [ ] **Step 2: 运行测试确认失败**

```bash
swift test --filter L10nTests 2>&1 | tail -10
```

Expected: 编译失败，缺少 `menuShowInFinder` / `menuFilterAgentHelp`。

- [ ] **Step 3: 实现**

在 `L10n.swift` 的 `menuOpenFinderHelp` 之后加入：

```swift
    public var menuShowInFinder: String { zh ? "在 Finder 中显示" : "Show in Finder" }
    public var menuFilterAgentHelp: String {
        zh ? "打开主窗口并只看该 agent" : "Open the main window filtered to this agent"
    }
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter L10nTests 2>&1 | tail -6
```

Expected: 全部通过。

- [ ] **Step 5: 提交**

```bash
git add Sources/AppCore/L10n.swift Tests/AppCoreTests/L10nTests.swift
git commit -m "feat(menubar): 补充 agent 行中英文案"
```

---

### Task 3: agent 行改为筛选 + 右键 Finder

**Files:**
- Modify: `Sources/AgentKeeperUI/MenuBarPanel.swift:35-73`
- Test: `Tests/AgentKeeperTests/ProbeMenuBar.swift:29-37`

- [ ] **Step 1: 改行组件**

把 `MenuBarAgentRow` 整体替换为：

```swift
/// agent 行：左键打开主窗口并筛选该 agent；右键在 Finder 中显示其 skill 根目录。
struct MenuBarAgentRow: View {
    let name: String
    let icon: String
    let skillCount: Int
    let targetDirectory: URL?
    let onSelect: () -> Void
    var l10n: L10n = L10n(lang: .zhHans)

    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer()
                Text("\(skillCount)")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(hovering ? Color(nsColor: .secondarySystemFill) : .clear)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .help(l10n.menuFilterAgentHelp)
        .contextMenu {
            Button(l10n.menuShowInFinder) {
                guard let targetDirectory else { return }
                NSWorkspace.shared.activateFileViewerSelecting([targetDirectory])
            }
            .disabled(targetDirectory == nil)
        }
    }
}
```

- [ ] **Step 2: 更新渲染探针**

把 `ProbeMenuBar` 里的 `MenuBarAgentRow` 调用改为：

```swift
        try probe(
            MenuBarAgentRow(
                name: "Claude Code",
                icon: MenuBarIcons.icon(for: "claude-code"),
                skillCount: 53,
                targetDirectory: URL(fileURLWithPath: "/tmp"),
                onSelect: {}
            ),
            name: "agent-row"
        )
```

- [ ] **Step 3: 运行探针确认通过**

```bash
swift test --filter ProbeMenuBar 2>&1 | tail -6
```

Expected: `Test run with 1 test passed`。

- [ ] **Step 4: 提交**

```bash
git add Sources/AgentKeeperUI/MenuBarPanel.swift Tests/AgentKeeperTests/ProbeMenuBar.swift
git commit -m "feat(menubar): agent 行左键筛选、右键 Finder"
```

---

### Task 4: 菜单面板接线

**Files:**
- Modify: `Sources/AgentKeeperUI/MenuSummarySection.swift:35-44`

- [ ] **Step 1: 传入 onSelect**

把 `ForEach` 里的调用改为：

```swift
                ForEach(agents) { entry in
                    MenuBarAgentRow(
                        name: entry.name,
                        icon: MenuBarIcons.icon(for: entry.id),
                        skillCount: entry.skillCount,
                        targetDirectory: skillRootDirectory(for: entry.id),
                        onSelect: {
                            env.openAgentFilter(entry.id)
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            openWindow(id: "main")
                        },
                        l10n: env.l10n
                    )
                }
```

- [ ] **Step 2: 构建确认**

```bash
swift build 2>&1 | grep -E "error:|warning:" | sort -u; echo BUILD_OK
```

Expected: 只输出 `BUILD_OK`。

- [ ] **Step 3: 提交**

```bash
git add Sources/AgentKeeperUI/MenuSummarySection.swift
git commit -m "feat(menubar): 点击 agent 打开主窗口并筛选"
```

---

### Task 5: 主窗口搜索词收口

**Files:**
- Modify: `Sources/AgentKeeperUI/RootView.swift:345-385`

- [ ] **Step 1: 改为绑定 env.searchText**

`SkillListView` 删除局部 `@State private var searchText`，body 顶部加 `@Bindable var env = env`，并把 `.searchable` 改为 `$env.searchText`；筛选读 `env.searchText`；`SkillListCore` 不再接收 searchText binding。

- [ ] **Step 2: 构建 + 全量测试**

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null
swift build 2>&1 | grep -E "error:|warning:" | sort -u
swift test --no-parallel 2>&1 | tail -3
```

Expected: 无 error/warning；`Test run with N tests passed`。

- [ ] **Step 3: 提交**

```bash
git add Sources/AgentKeeperUI/RootView.swift
git commit -m "feat(menubar): 主窗口响应搜索重置"
```

---

### Task 6: 手工验收

- [ ] **Step 1: 构建并运行 App**

```bash
scripts/build-app.sh release
osascript -e 'quit app "AgentKeeper"' 2>/dev/null
rm -rf /Applications/AgentKeeper.app
cp -R AgentKeeper.app /Applications/
open /Applications/AgentKeeper.app
```

- [ ] **Step 2: 验证**

1. 点状态栏图标 → 点某个 agent → 主窗口前置，侧栏该 agent 高亮，列表只剩它的 skill
2. 在主窗口搜索框输入内容 → 再点另一个 agent → 搜索框被清空，列表切到新 agent
3. 右键 agent 行 → 「在 Finder 中显示」仍可打开目录
4. 关闭主窗口 → 再点 agent → 主窗口重新出现且筛选正确
