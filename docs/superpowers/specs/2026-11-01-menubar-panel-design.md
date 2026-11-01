# 菜单栏面板美化设计（Raycast 式迷你面板）

日期：2026-11-01
状态：已确认（方向 A）

## 背景与目标

菜单栏弹窗（`MenuBarExtra` window 风格 + `MenuSummarySection`）目前是原始的 Section 列表：千篇一律的绿色对勾、左对齐文字、无 hover 质感。目标用户画像（同时跑多个 AI agent 的开发者）的审美标杆是 Raycast / Linear：信息密度高、留白克制、原生控件质感、tabular 数字、动效含蓄。

设计目标：把弹窗从「状态罗列」升级为「开发者速度感的迷你面板」，同时不越界——菜单是橱窗（状态 + 快捷动作），完整管理仍在主窗口。

## 视觉规范

- 整体着装用 macOS 系统语义色（`windowBackgroundColor` 体系 / `.secondary` / `.quaternary` hover 背景），仅两处点缀 Claude 陶土橙 accent：主按钮、（可选）skill 总数徽章。沿用 ClaudePalette 纪律。
- 数字右对齐 + `.monospacedDigit()`（tabular），行高约 28px，分隔线密度规整。
- 深浅色跟随系统（已由 AppSettingsStore `effectiveColorScheme` 保证，面板内不硬编码颜色）。

## 结构（三层）

1. **头部行**：App 定位锚点 + 「N agents · N skills」摘要行，数字 tabular 右对齐。
2. **agent 状态区**（只列实际安装的 agent）：
   - 左：按 agent ID 语义化的 SF Symbol 图标（终端类 `terminal`、Gemini/Cursor 类 `sparkles`/`cursorarrow` 等；未知 ID 回落 `terminal`），替代千篇一律的绿色对勾。
   - 中：agent 名称。
   - 右：skill 数（tabular，`.secondary`）。
   - 行级 hover 高亮（`quaternary` 圆角背景）；**点击行在 Finder 打开该 agent 的第一个 skill 根目录**（`NSWorkspace.activateFileViewerSelecting`，与文件清单交互同构）。
3. **操作区**：
   - 「打开主窗口」全宽主按钮（accent 视觉）。
   - 「立即扫描」行：运行中显示 inline `ProgressView`，禁用态收口。
   - 底部收「退出 AgentKeeper」小字行（⌘Q 标注保留）。
   - 空态：扫描中显示「正在扫描…」，未扫描/无 agent 显示引导文案。

## 组件与数据流

- `MenuSummarySection`（AgentKeeperUI）重构，成员拆分：
  - `MenuBarHeaderRow`：头部摘要。
  - `MenuBarAgentRow`：agent 行（icon / 名称 / 数量 / hover / 点击打开目录）。
  - `MenuPanelActions`：操作区（主按钮 / 扫描 / 退出）。
- 复用 `MenuBarSummary.build(state:skills:)`（AppCore，不变）；agent 目录取 `agent.skillRoots.first?.path`。
- 图标映射为纯函数 `MenuBarIcons.icon(for agentID: AgentID) -> String`，放 AppCore（可测），UI 只消费。

## 错误处理

- agent 无 skillRoots：整行可点但点击静默无动作（或禁用 hover 光标），不弹错误。
- 扫描失败态沿用 `store.state.scan` 既有展示，不新增错误面板。

## 测试

- AppCore 单测：`menuBarIcon(for:)` 映射（已知 ID → 指定图标、未知 ID → fallback）。
- UI 快照/探针测试：`MenuBarHeaderRow`、`MenuBarAgentRow` 渲染探针（复用 ProbeRender 模式，写 `/tmp/ak-ui` 前先建目录）。
- 纪律：TDD RED→GREEN；`swift build` 0-warning；全量 suite 全绿后提交。

## 不做（YAGNI）

- 冲突小红点 / 最近变更列表（方向 C 元素，记 backlog）。
- 面板内直接管理 skill（橱窗越界）。

## 相关 backlog 联动

完成后可把「菜单栏 hover 打开 skill 目录」经验复用到 ⌘K / Quick Look（roadmap 既有项）。
