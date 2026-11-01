# 菜单栏 Raycast 式迷你面板 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 MenuBarExtra 弹窗从原始 Section 列表升级为三层结构（头部摘要 / agent 状态行 / 操作区）的 Raycast 风格迷你面板。

**Architecture:** AppCore 新增纯函数图标映射（可测）；AgentKeeperUI 新增 `MenuBarPanel.swift`（HeaderRow / AgentRow / PanelActions 三个小组件）；重构 `MenuSummarySection` 组装并供给可执行层。数据流复用 `MenuBarSummary.build`，不新增状态。

**Tech Stack:** SwiftUI / Swift Testing / NSWorkspace（Finder 定位）。

**Spec:** `docs/superpowers/specs/2026-11-01-menubar-panel-design.md`

---

### Task 1: 图标映射纯函数（AppCore）

**Files:**
- Modify: `Sources/AppCore/MotionAndMenu.swift`（文件末尾追加）
- Test: `Tests/AppCoreTests/MenuBarIconsTests.swift`（新建）

- [ ] **Step 1: 写失败测试**

```swift
import Testing
import DomainKit
@testable import AppCore

/// 菜单栏 agent 行语义图标：已知 ID → 指定图标，未知 ID 回落 terminal。
@Suite struct MenuBarIconsTests {
    @Test func knownAgentIDsMapToSemanticIcons() {
        #expect(MenuBarIcons.icon(for: "claude-code") == "chevron.left.forwardslash.chevron.right")
        #expect(MenuBarIcons.icon(for: "opencode") == "chevron.left.forwardslash.chevron.right")
        #expect(MenuBarIcons.icon(for: "codex") == "chevron.left.forwardslash.chevron.right")
        #expect(MenuBarIcons.icon(for: "cursor") == "cursorarrow.rays")
        #expect(MenuBarIcons.icon(for: "gemini") == "sparkles")
        #expect(MenuBarIcons.icon(for: "qwen") == "sparkles")
        #expect(MenuBarIcons.icon(for: "pi") == "terminal")
        #expect(MenuBarIcons.icon(for: "oh-my-pi") == "terminal")
        #expect(MenuBarIcons.icon(for: "openclaw") == "terminal")
        #expect(MenuBarIcons.icon(for: "agents-shared") == "person.2")
    }

    @Test func unknownIDFallsBackToTerminal() {
        #expect(MenuBarIcons.icon(for: "future-agent") == "terminal")
        #expect(MenuBarIcons.icon(for: "") == "terminal")
    }
}
```

- [ ] **Step 2: 跑测试确认 RED**

Run: `swift test --filter MenuBarIconsTests 2>&1 | grep -E "error:|✘" | head -3`
Expected: `cannot find 'MenuBarIcons' in scope`

- [ ] **Step 3: 最低实现**

在 `Sources/AppCore/MotionAndMenu.swift` 末尾追加：

```swift
/// 菜单栏 agent 行的语义 SF Symbol（Raycast 式面板）。未知 ID 统一回落 terminal。
public enum MenuBarIcons {
    private static let mapping: [AgentID: String] = [
        "claude-code": "chevron.left.forwardslash.chevron.right",
        "opencode": "chevron.left.forwardslash.chevron.right",
        "codex": "chevron.left.forwardslash.chevron.right",
        "cursor": "cursorarrow.rays",
        "gemini": "sparkles",
        "qwen": "sparkles",
        "pi": "terminal",
        "oh-my-pi": "terminal",
        "openclaw": "terminal",
        "agents-shared": "person.2",
    ]

    public static func icon(for agentID: AgentID) -> String {
        mapping[agentID] ?? "terminal"
    }
}
```

- [ ] **Step 4: 跑测试确认 GREEN + 全量绿**

Run: `swift test 2>&1 | grep -E "Test run with" | tail -1`
Expected: 全绿（276 → 278）

- [ ] **Step 5: Commit**

```bash
git add Sources/AppCore/MotionAndMenu.swift Tests/AppCoreTests/MenuBarIconsTests.swift
git commit -m "feat:MenuBarIcons 语义图标映射(菜单栏面板 Task 1)"
```

### Task 2: 面板三组件（AgentKeeperUI）

**Files:**
- Create: `Sources/AgentKeeperUI/MenuBarPanel.swift`
- Test: `Tests/AgentKeeperTests/ProbeMenuBar.swift`（新建，参照 ProbeRender 模式）

- [ ] **Step 1: 写失败测试（渲染探针：三组件可出真实像素）**

```swift
import Foundation
import Testing
import SwiftUI
import AppKit
import DomainKit
@testable import AgentKeeperUI

/// 菜单栏面板组件：NSHostingView 位图渲染探针（出真实像素才算渲染成功）。
@MainActor
@Suite struct ProbeMenuBar {
    @Test func panelComponentsRenderToPixels() throws {
        func probe(_ view: some View, name: String) throws {
            let hosted = NSHostingView(rootView: view.frame(width: 260))
            hosted.frame = NSRect(x: 0, y: 0, width: 260, height: 120)
            hosted.layoutSubtreeIfNeeded()
            let rep = hosted.bitmapImageRepForCachingDisplay(in: hosted.bounds)!
            hosted.cacheDisplay(in: hosted.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try FileManager.default.createDirectory(atPath: "/tmp/ak-ui", withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: "/tmp/ak-ui/menubar-\(name).png"))
            #expect(png.count > 1000) // 非全透明才有内容
        }

        try probe(
            MenuBarHeaderRow(agentCount: 3, totalSkills: 86),
            name: "header"
        )
        try probe(
            MenuBarAgentRow(
                name: "Claude Code",
                icon: MenuBarIcons.icon(for: "claude-code"),
                skillCount: 53,
                targetDirectory: URL(fileURLWithPath: "/tmp")
            ),
            name: "agent-row"
        )
        try probe(
            MenuPanelActions(isScanning: false, onOpenMain: {}, onScan: {}, onQuit: {}),
            name: "actions"
        )
    }
}
```

- [ ] **Step 2: 确认 RED**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: `cannot find 'MenuBarHeaderRow' in scope`

- [ ] **Step 3: 实现组件（新建 `Sources/AgentKeeperUI/MenuBarPanel.swift`）**

```swift
import SwiftUI
import AppKit
import DomainKit
import AppCore

// MARK: - 头部摘要行

/// 头部：面板锚点 + 摘要（tabular 数字，右对齐灰阶层级）。
struct MenuBarHeaderRow: View {
    let agentCount: Int
    let totalSkills: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 12))
                .foregroundStyle(ClaudePalette.accent)
            Text("AgentKeeper")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(agentCount) agents · \(totalSkills) skills")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - agent 状态行

/// agent 行：语义图标 + 名称 + tabular skill 数；hover 高亮；点击在 Finder 打开其 skill 根目录。
struct MenuBarAgentRow: View {
    let name: String
    let icon: String
    let skillCount: Int
    let targetDirectory: URL?

    @State private var hovering = false

    var body: some View {
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
        .onTapGesture {
            guard let targetDirectory else { return }
            NSWorkspace.shared.activateFileViewerSelecting([targetDirectory])
        }
        .help("在 Finder 中打开该 agent 的 skills 目录")
    }
}

// MARK: - 操作区

/// 操作区：全宽主按钮（accent）+ 扫描行 + 底部退出小字。
struct MenuPanelActions: View {
    let isScanning: Bool
    let onOpenMain: () -> Void
    let onScan: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Button(action: onOpenMain) {
                Text("打开主窗口")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(ClaudePalette.accent)

            Button(action: onScan) {
                HStack {
                    Text(isScanning ? "正在扫描…" : "立即扫描")
                        .font(.system(size: 12))
                    Spacer()
                    if isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(nsColor: .secondarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isScanning)

            Button(action: onQuit) {
                HStack {
                    Text("退出 AgentKeeper")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("⌘Q")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .buttonStyle(.plain)
        }
    }
}
```

- [ ] **Step 4: GREEN**

Run: `swift test --filter ProbeMenuBar 2>&1 | grep -E "Test run with|✘" | head -3`
Expected: 全绿

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentKeeperUI/MenuBarPanel.swift Tests/AgentKeeperTests/ProbeMenuBar.swift
git commit -m "feat:菜单栏面板三组件(头部/agent行/操作区,Raycast 式) (Task 2)"
```

### Task 3: 组装重构 MenuSummarySection

**Files:**
- Modify: `Sources/AgentKeeperUI/MenuSummarySection.swift`（全文替换）

- [ ] **Step 1: 重写为组件组装（保持 public 入口 `MenuSummarySection(env:)` 不变，可执行层零改动）**

完整替换后的内容：

```swift
import SwiftUI
import AppKit
import AppCore

/// 菜单栏摘要面板（Raycast 式三层迷你面板）。
/// 职责：摘要（状态橱窗）+ 快捷动作；完整管理仍在主窗口。
public struct MenuSummarySection: View {
    let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    public init(env: AppEnvironment) {
        self.env = env
    }

    public var body: some View {
        let summary = MenuBarSummary.build(
            state: env.store.state,
            skills: env.catalogStore.current
        )
        let agents = summary.agentEntries.filter(\.installed)
        let isScanning = env.store.state.scan.phase == .running

        VStack(spacing: 0) {
            MenuBarHeaderRow(agentCount: agents.count, totalSkills: summary.totalSkills)

            if agents.isEmpty {
                Text(isScanning ? "正在扫描…" : "尚未发现已安装的 agent")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(agents) { entry in
                    MenuBarAgentRow(
                        name: entry.name,
                        icon: MenuBarIcons.icon(for: entry.id),
                        skillCount: entry.skillCount,
                        targetDirectory: skillRootDirectory(for: entry.id)
                    )
                }
            }

            Divider().padding(.vertical, 6)

            MenuPanelActions(
                isScanning: isScanning,
                onOpenMain: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                },
                onScan: {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    Task { await env.scanNow() }
                },
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .frame(width: 260)
    }

    /// 该 agent 的第一个 skill 根目录（Finder 定位用；无则 nil，行不可点）。
    private func skillRootDirectory(for agentID: AgentID) -> URL? {
        env.store.state.agents
            .first(where: { $0.id == agentID })?
            .skillRoots.first?.path
    }
}
```

- [ ] **Step 2: 全量回归（suite 全绿 + 0-warning）**

Run: `swift build 2>&1 | grep -cE "warning:|error:"`
Expected: `0`

Run: `swift test 2>&1 | grep -E "Test run with" | tail -1`
Expected: 全绿

- [ ] **Step 3: 真机验证**

Run: `swift test --filter ProbeMenuBar >/dev/null && open /tmp/ak-ui/menubar-header.png`（人工目检三张探针图）
Expected: 视觉符合 spec（图标语义 / tabular 数字 / hover / accent 主按钮）

- [ ] **Step 4: Commit + 推送**

```bash
git add Sources/AgentKeeperUI/MenuSummarySection.swift
git commit -m "feat:菜单栏面板组装重构——三层迷你面板落地(Raycast 式)"
git push
```
