# Proposal: add-linux-app

## Why

macOS 版 AgentKeeper 的 GUI（三面板主窗口 + 菜单栏面板 + 设置）是其核心产品价值，Linux 用户（Ubuntu 为主力发行版）目前只有 CLI。本 change 按**已确认的 S1 双栈架构**（`docs/research/2026-11-21-linux-gui-port-report.md` §4.4，2026-11-21 用户确认：两套视图为长期正式形态，非过渡方案）交付 Linux/Ubuntu GUI 第一版，并通过「共享展示层 + 双栈复用约定」把两端重复面压到最小。

## What Changes

- 新增 SwiftPM target `AgentKeeperShared`：把 AppEnvironment、AppSettingsStore、展示模型（Zone/SidebarAgent/SkillPreview）、动效策略决策、Markdown 块解析、展示逻辑 ViewModel、设计令牌（色板 hex/间距/字号阶）从 AgentKeeperUI 移入共享层
- 新增 `PlatformAdapter` 协议收敛平台行为（reveal 文件/打开 URL/选目录/减少动效探测/激活/退出/托盘挂载），macOS 与 Linux 各一份实现
- macOS 栈（AgentKeeperUI）：改造为薄壳视图，行为与视觉零变化
- 新增 `AgentKeeperUILinux` target（SwiftCrossUI + GtkBackend）：主窗口（三面板映射为 SCUI 布局）、设置窗口、SKILL.md 预览；`@main` 入口按平台装配
- Linux 托盘：AppIndicator/StatusNotifierItem 接入，展示摘要与快速入口；GNOME 裸装无托盘环境降级为仅主窗口并在界内提示
- Linux 打包与分发：`scripts/build-linux-app.sh` 产出 tar.gz 与 .deb（含 .desktop、hicolor PNG 图标）；`xdg-open` 打开文件/目录；更新提示走 gh-release 检查 + 打开下载页
- CI release 增加 Linux app 产物；README 下载矩阵与 Linux 说明、托盘环境声明
- **BREAKING**（无）：macOS 侧行为、视觉、产物不变

## Capabilities

### New Capabilities

- `linux-app-shell`: Linux GUI 外壳与分发行为——主窗口/设置在 Ubuntu 的可用性、托盘常驻入口（含降级）、文件/目录打开、安装形态（.deb/tar.gz）与更新提示

### Modified Capabilities

- `app-ui`: 三面板交互习惯、常驻入口形态、动效质感三项要求平台中性化（macOS 保持既有语义，Linux 以原生等价物满足同一行为要求）

## Impact

- **代码**：`Sources/AgentKeeperShared`（新）、`Sources/AgentKeeperUILinux`（新）、`Sources/AgentKeeperUI`（薄壳化移动）、`Sources/AgentKeeper`（入口装配）、`Sources/AppCore`（接收共享下沉项）、`Package.swift`（新增 target + SwiftCrossUI 依赖）
- **构建/CI**：`scripts/build-linux-app.sh`（新）、ci.yml release 产物扩展
- **依赖**：新增 SwiftCrossUI（moreSwift，GTK4 backend）、系统依赖 GTK4（Ubuntu 24.04 运行库）
- **前置**：`add-linux-core-portability`（core 平台无关 + Linux CI）
- **文档**：INSTALL.md、README 下载矩阵、AGENTS.md 双栈复用约定
