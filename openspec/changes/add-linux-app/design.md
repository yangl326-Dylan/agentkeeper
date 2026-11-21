# Design

## Context

S1 双栈架构已确认（报告 §4.4，2026-11-21）：macOS 保留 SwiftUI，Linux 用 SwiftCrossUI（GtkBackend），两套视图为长期正式形态；靠「共享展示层 + 复用约定」压缩双端差异。SCUI 映射表已查证（报告 §4.3）：`NavigationSplitView`/`List`/`Picker`/alerts/sheets/contextMenus/`Commands` 有同名或等价物；缺口为 `MenuBarExtra`（托盘自接）、`.searchable`（TextField 替代）、`Settings` scene（自建窗口）。前置 change `add-linux-core-portability` 已完成 core 平台无关与 Linux CI。开发机即 Ubuntu 24.04（有显示服务），Linux 侧可本地构建运行验证；macOS 侧零回归靠机械式移动 + CI。

## Goals / Non-Goals

**Goals:**
- Ubuntu 24.04 GUI 第一版：主窗口 + 设置 + 托盘 + 打包（tar.gz/.deb），本地可安装运行
- 双端复用最大化：逻辑/模型/令牌/文案 100% 共享，视图为薄壳
- macOS 视觉与行为零变化（视图薄壳化只是移动代码）

**Non-Goals:**
- AppImage（.deb + tar.gz 先行，后续可加）
- 应用内静默自更新（只做检查 + 跳下载页）
- Windows / 移动端
- macOS UI 视觉调整或新功能

## Decisions

1. **共享展示层 target `AgentKeeperShared`**（依赖 AppCore；被两个 UI 栈依赖）：移入 AppEnvironment（@Observable 环境）、AppSettingsStore、ZoneModels/SidebarAgentModel/SkillPreviewModel、MotionCategory 纯决策、Markdown 块解析、主窗口展示 ViewModel（自 RootView 剥离）、ClaudePalette 令牌（hex 常量）。平台探测类依赖（reduceMotion 等）经 `PlatformAdapter` 注入。
2. **`PlatformAdapter` 协议收敛平台行为**：`revealInFileManager(url)` / `openURL` / `chooseDirectory` / `isReduceMotionEnabled` / `activateApp` / `terminate` / `mountTray(...)`。macOS 实现复用现有 NSWorkspace/NSApplication 调用；Linux 实现 xdg-open/ gio / AppIndicator。共享层只见协议。
3. **Linux UI = SwiftCrossUI + GtkBackend**：`@main` 入口 `#if os` 装配（macOS=现有 SwiftUI App；Linux=SCUI App）。SCUI 版视图按报告 §4.3 映射表落地；`.searchable` 用顶部 TextField 过滤（共享 ViewModel 同一过滤逻辑，macOS 搜索框与 Linux 输入框喂同一 VM）；设置用独立 `WindowGroup`。
4. **托盘（Linux）= AppIndicator**：经 DBus（StatusNotifierItem）最小实现或引入轻量库（task 内定案，倾向自写最小 DBus 客户端避免重依赖）；图标用共享令牌生成的 PNG；菜单项：摘要（只读行）、打开主窗口、立即扫描、退出。降级：DBus 注册失败 → 仅主窗口 + 界内提示（spec 降级场景）。
5. **复用约定（写入 AGENTS.md，评审纪律）**：薄壳纪律（视图无逻辑）、文件镜像成对（`RootView`↔`LinuxRootView`）、设计令牌单一定义、文案全走 L10n、共享 VM 单测双 CI 平台全绿。视图文件头注释声明成对文件路径。
6. **打包**：`scripts/build-linux-app.sh release [--deb|--targz]`：`swift build --static-swift-stdlib` → 组装 `/usr/bin/agentkeeper`、`/usr/share/applications/agentkeeper.desktop`、hicolor PNG（由 macOS release job 预生成入 `assets/icons/`，Linux 只消费）、`DEBIAN/control`（Depends: libgtk-4-1 等）。tar.gz 提供便携目录布局 + README。
7. **验证策略（自我验收，无需用户确认）**：本机 Ubuntu 24.04 全链路——`swift build/test` 双绿；GUI 进程启动冒烟（DISPLAY 可用，截图留档）；`ak`/GUI 共存；.deb 本地 `apt install` + GNOME 搜索可见；托盘注册成功（本机桌面）或降级路径触发；共享 VM 测试全绿。macOS 零回归：薄壳化改动全部为「移动 + import 调整」，推送后 CI macos job 全绿为准。

## Risks / Trade-offs

- SCUI 演进中 API 变动 → 锁定具体版本（精确版本号依赖），升级走独立小 change
- `@Observable` AppEnvironment 与 SCUI 状态体系集成方式待 PoC 确认（报告 §4.3 🟡 项）→ 任务 1 作为首任务，失败面（Animation、searchable 替代）有既定降级实现
- 本机 GNOME 若无 AppIndicator 支持则托盘只能测降级路径 → 降级路径本身是 spec 场景，正向路径留 CI/实机验证说明
- macOS 侧无法本地编译 → 薄壳化严格限制为机械移动；RootView 剥离逻辑分多次小步提交，每步 CI 验证
- .deb 依赖声明与真实运行库差异 → 本机 apt install 实测闭环
