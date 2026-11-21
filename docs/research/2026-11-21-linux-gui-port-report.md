# Ubuntu/Linux 支持可行性报告（单仓库双平台构建：macOS app + Linux app + CLI）

日期：2026-11-21 · 方法：全量代码盘点（逐项核验平台依赖面）→ 移植矩阵 → 构建矩阵 → 分阶段路线
用途：为「本仓库同时产出 macOS app / Ubuntu app / 双平台 CLI」立项提供决策输入；确认后走 OpenSpec 拆 change
目标形态：**一份 Swift 代码库、一套 core，四个发布产物**

| 产物 | 平台 | 形态 |
|---|---|---|
| AgentKeeper.app | macOS 15+ | .app bundle（现状保持） |
| AgentKeeper（GUI） | Ubuntu 24.04+（Linux） | 二进制 + .desktop（.deb / AppImage 分发） |
| ak | macOS / Linux | 单二进制 zip |

---

## 一、结论先行

1. **core（DomainKit / InfraKit / AppCore ≈ 6.8k 行）基本可移植**：Foundation / Process / UserDefaults / `homeDirectoryForCurrentUser` / SQLite3 在 Linux Swift 均可用。真正要动的只有 **4 处小点**（§3 矩阵）。
2. **`ak` CLI 与 GUI 共用 core**——P0 完成后 Linux 版 `ak` 白拿，独立发布、立即可用。
3. **GUI 的事实约束**：SwiftUI 无 Linux 实现，Linux app 的**视图层**需要一个 Swift 生态内的渲染栈（SwiftCrossUI/GTK4 是主候选，§4）。这不改变仓库形态：**macOS 侧 SwiftUI 视图原样保留，Linux 侧加一个独立 UI target**，两层共享同一份 AppCore。
4. **组织方式 = target 分平台 + 条件编译收口**：`#if os(...)` 只允许出现在「平台入口」与「平台适配器」两类文件；core 层零 os 分支，用 CI 双平台全绿强制这条纪律。
5. **推荐路线**：P0 core 可移植化 + Linux CI + CLI 上 Linux（3–5 人日）→ P1 Linux UI target PoC（2–3 人日）→ P2 Linux app MVP + 打包（10–15 人日）→ P3 分发与更新（3–5 人日）。

---

## 二、现状盘点

### 2.1 分层与平台性

| 层 | 规模 | 平台性 |
|---|---|---|
| DomainKit（纯模型） | ~0.5k 行 | ✅ 纯 Foundation，直接可用 |
| InfraKit（扫描/索引/分发） | ~3.1k 行 | 🟡 3 处平台点（§3 #1/#2/#6） |
| AppCore（状态/服务/CLI） | ~3.2k 行 | 🟢 1 处 AppKit 泄漏（UpdateModel.terminate）+ 动效层 import SwiftUI |
| AgentKeeperUI（SwiftUI 视图） | ~3.1k 行 | 🔴 macOS-only（保留，仅服务 macOS 产物） |
| AgentKeeper 入口（@main） | 57 行 | 🔴 MenuBarExtra / Settings / CommandGroup（按平台拆入口） |
| ak 入口 | 小 | ✅ 纯 core，P0 后即双平台 |

### 2.2 现有构建/发布链（改造基底）

- `scripts/build-app.sh`：swift build → 组装 .app（Info.plist + icns + ad-hoc codesign）；`UNIVERSAL=1` 双架构
- `.github/workflows/ci.yml`：macos-15 单 job；0-warning 纪律；release 时产 `AgentKeeper-cli-macos.zip` + `AgentKeeper-app-macos.zip` 上传 gh-release
- Linux 侧目前**无任何 job、无打包脚本**——这是本次要补的半边

---

## 三、core 层 Linux 移植矩阵（P0 范围）

| # | 点 | 现状 | Linux 对应 | 改动量 |
|---|---|---|---|---|
| 1 | sha256 指纹 | `import CryptoKit`（SkillParsing.swift） | **swift-crypto**（Apple 官方支持 Linux，API 同名）。建议双平台统一切 swift-crypto，一份代码 | 小（import + Package.swift 依赖） |
| 2 | 文件监听 | `import CoreServices` FSEvents（FSEventMonitor.swift，整批回调语义） | inotify（递归需自行对子目录逐个 add_watch）。抽 `FileSystemMonitoring` 协议：macOS=FSEvents 实现，Linux=inotify 实现，上层不变 | 中 |
| 3 | 应用内更新 | AppUpdateInstaller：ditto / xattr / codesign / .app 原子替换 | 整文件 `#if os(macOS)` 隔离；Linux 通道 P3 再做（查 gh-release + 打开下载页） | 小 |
| 4 | AppKit 泄漏 | UpdateModel.swift `NSApplication.terminate` 默认闭包 | 改注入式默认值，由 UI 层注入真正退出动作 | 小 |
| 5 | 动效层 | MotionAndMenu.swift `import SwiftUI`（Animation 策略） | SwiftUI 类型随 Linux 目标编不过 → `MotionPolicy` 移入 AgentKeeperUI（macOS 视图层），AppCore 保持平台无关 | 小 |
| 6 | git 路径 | 默认 `/usr/bin/git` 硬编码 | Linux 同路径可用；加 `which git` PATH 回退 | 极小 |
| 7 | SQLite3 | `import SQLite3` | Linux 链接系统 libsqlite3（CI/构建文档装 `libsqlite3-dev`） | 无代码改动 |
| 8 | UserDefaults / home / Process | Foundation | Linux corelibs-foundation 均可用（UserDefaults 落盘 plist） | 无改动 |

**测试面**：`AgentKeeperTests` 内 AppKit 探针（ProbeButton / ProbeMenuBar / UISnapshotTests 等）→ 文件级 `#if os(macOS)` 排除；DomainKit / InfraKit / AppCore 三组测试要求 Linux 全绿——这是 P0 验收标准，也是「core 平台无关」的 CI 强制防线。

---

## 四、Linux app 的视图层选型（同一仓库内的双 UI target）

### 4.1 事实约束

- SwiftUI 无 Linux 版本；SwiftOpenUI / OpenSwiftUI（社区复刻）2026 年仍属实验性，不可押注。
- 因此 Linux GUI 必须在 Swift 生态内选一个渲染栈。**这不影响仓库形态与 core 复用**——只是 `Sources/` 下多一个 UI target。

### 4.2 选型结论：SwiftCrossUI（2026-11 文档查证）

**结论：SwiftCrossUI（Linux=GtkBackend）是最接近 SwiftUI 的方案，且支持「单栈收敛」形态。**

选型证据（官方文档 2026-11 核实）：
- API 同源：`App` 协议 + `Scene`（`WindowGroup`）、`@State` / `@Binding` / `@AppStorage` / `@Environment` 与 SwiftUI 同名同语义；官方口径"API similar but not identical to SwiftUI"
- 控件覆盖（对本仓库实际用到的面）：`NavigationSplitView` / `NavigationStack`（有官方示例）、`Table`（SpreadsheetExample）、alerts / sheets / file pickers（WindowingExample）、context menus、`Commands`（应用级菜单）、`Path`、多窗口（WindowingExample）、tooltips、date pickers
- **跨端关键事实**：`AppKitBackend`（macOS）官方标注 **"Supports all SwiftCrossUI features"**；`GtkBackend`（Linux）标注 "supports most features"。⇒ 同一份 SCUI 视图可双端原生渲染，「单栈收敛」在技术上成立
- 工具链：Linux 热重载已支持；`Gtk3Backend` 可覆盖老发行版（本项目目标 Ubuntu 24.04+ 不需要）
- 战略加分：WinUIBackend/iOS/Android backend 在路线图上——未来 Windows/移动端复用同一套 UI 代码

### 4.3 本仓库 SwiftUI 用面 → SwiftCrossUI 映射表（PoC 验收清单）

| 现用法（统计） | SCUI 对应 | 判定 |
|---|---|---|
| `App` + `Window(id:"main")` | `App` + `WindowGroup`（支持多窗口/窗口属性控制） | ✅ |
| `NavigationSplitView` 三栏 | 同名 `NavigationSplitView` | ✅ |
| `List` ×9 | 同名 | ✅ |
| `Table`（如需） | 同名（SpreadsheetExample 佐证） | ✅ |
| `Picker` ×4 | 同名，API 略异（`init(of:selection:)` 用 `Binding<Value?>`） | ✅ 小改 |
| `.alert` ×3 / `.sheet` ×2 | alerts / sheets 官方支持 | ✅ |
| `.contextMenu` ×2 | context menus 支持 | ✅ |
| `CommandGroup` + ⌘R | `Commands`（应用级菜单条目） | ✅ 大体 |
| `NSWorkspace.open` / Finder 定位 | backend 内建 URL handling / **RevealFiles** feature | ✅ |
| `Settings` scene（⌘,） | 无对应 scene → 自建设置窗口（WindowGroup 多窗口） | 🟡 重构小 |
| `.searchable` ×1 | 无直接对应 → TextField 过滤实现 | 🟡 自实现 |
| `.toolbar` ×2 | 无直接对应 → 页面内工具条重构 | 🟡 重构小 |
| **`MenuBarExtra(.window)` 菜单栏面板** | **无对应物**：两端各自自接（macOS 复用现有 NSStatusItem 代码；Linux AppIndicator） | 🔴 最大缺口 |
| `@Observable` AppEnvironment 接入 | SCUI 状态体系为 `@State`/`@Environment`；外部 Observable 接入方式 PoC 确认 | 🟡 PoC 验证 |
| `.tint` / `preferredColorScheme` / 动效 | 系统主题变化监听内建；accent 自定义有 API；Animation 支持面 PoC 确认 | 🟡 PoC 验证 |

### 4.4 收敛形态（已确认决策：S1 双栈定案）

> **用户已确认（2026-11-21）**：采用 **S1 双栈**——macOS 保留 SwiftUI、Linux 新增 SCUI target，两套视图是**长期正式形态**（非过渡方案）；同时通过「共享展示层 + 双栈复用约定」把两端的重复面压到最小（见 §4.6）。

| | S1 双栈（**定案**） | S2 单栈（不采用） |
|---|---|---|
| 形态 | macOS 保留 SwiftUI（现状），Linux 新增 `AgentKeeperUILinux`（SCUI） | 一套 SCUI 视图跑双端 |
| 平台差异 | 两套视图文件（靠共享层把差异限制在"薄壳"内） | 视图层零差异 |
| 代价 | 长期维护两套视图；每功能 UI 薄壳做两遍 | 重写 ~3.1k 行 SwiftUI + macOS 0.5.x 体验回归风险 |
| 风险 | 低（macOS 旗舰体验零回归） | 中（SCUI 演进中） |
| 估量 | Linux MVP 8–12 人日 | — |

托盘是 S1 共同缺口：macOS 侧现有 `MenuBarIcon`/`MenuBarPanel`（NSStatusItem/NSImage）不动；Linux 侧接 AppIndicator（Ubuntu 默认支持，GNOME 裸装需扩展，README 声明；首发可降级为仅主窗口）。

### 4.5 仓库结构改造（Package.swift 草案）

```swift
targets: [
    .target(name: "DomainKit"),
    .target(name: "InfraKit", dependencies: ["DomainKit"]),      // P0 后平台无关
    .target(name: "AppCore", dependencies: ["DomainKit", "InfraKit"]),  // P0 后平台无关
    .target(name: "AgentKeeperShared", dependencies: ["AppCore", ...]), // 新增：共享展示层（§4.6）
    .target(name: "AgentKeeperUI", dependencies: ["AgentKeeperShared", ...]),          // macOS SwiftUI 薄壳（保持）
    .target(name: "AgentKeeperUILinux", dependencies: ["AgentKeeperShared", "SwiftCrossUI"]), // 新增（P1）
    .executableTarget(name: "AgentKeeper", dependencies: [...]),  // @main 内 #if os 分平台选 App
    .executableTarget(name: "ak", dependencies: [...]),           // 双平台
    ...
]
```

- 入口文件内 `#if os(macOS)` 用现有 SwiftUI App；`#elseif os(Linux)` 用 SCUI App——`platforms: [.macOS(.v15)]` 声明不影响 Linux 构建
- **纪律**：os 条件编译只允许出现在「入口 + 平台适配器（FSEventMonitor/UpdateInstaller）」两类文件；core 其余部分零 os 分支

### 4.6 双栈复用约定与设计（S1 定案的核心设计）

目标：两套视图只是「薄壳」，一切逻辑、模型、令牌、文案都在共享层——双端差异被结构性压缩。

**新增共享展示层 target `AgentKeeperShared`**（AppCore 与两个 UI 栈之间；平台无关，Linux CI 强制）：

| 从 AgentKeeperUI 移入共享层 | 内容 | 备注 |
|---|---|---|
| `AppEnvironment`（486 行） | @Observable 环境/引导/扫描挂载 | `NSWorkspace.reduceMotion` 探测改为 `PlatformAdapter` 注入 |
| `AppSettingsStore`（75 行） | 设置持久化 | UserDefaults 双平台可用 |
| `ZoneModels` / `SidebarAgentModel` / `SkillPreviewModel` | 展示模型 | 现成平台无关 |
| `MotionPolicy`（自 MotionAndMenu.swift） | 动效策略决策 | SwiftUI `Animation` 构造分栈（P0 已列） |
| Markdown 解析器（`MarkdownDocument` 内纯解析部分） | 块解析（已有 MarkdownBlockParserTests） | 解析共享、渲染分栈 |
| `RootView` 内展示逻辑（行构建/过滤/状态文案组装） | 抽为共享 ViewModel | 从 1168 行中剥离逻辑 |
| `ClaudePalette` 色值 | 设计令牌（hex/色板常量） | `Color` 构造分栈实现 |

**留在 macOS 栈**：`AppStartup`、`MenuBarIcon`、`MenuBarPanel`、`MenuSummarySection` 及全部 SwiftUI 视图文件（改造为薄壳）。
**新增 Linux 栈 `AgentKeeperUILinux`**：镜像视图文件 + SCUI App 入口 + Linux `PlatformAdapter` 实现。

**六条复用约定（评审纪律，写入 AGENTS.md/贡献文档）**：

1. **薄壳纪律**：视图文件只做 binding + 布局；任何 if/格式化/排序逻辑进共享 ViewModel——VM 有单测，双端共享同一测试
2. **平台适配点协议化**：`PlatformAdapter` 协议收敛全部平台行为（`revealInFileManager` / `openURL` / `openDirectoryPicker` / `reduceMotion` / `activateApp` / `terminate` / 托盘挂载），每栈一份实现，共享层只见协议
3. **文件镜像约定**：每屏一个视图文件，双端成对同名（`RootView` ↔ `LinuxRootView`），功能变更必须成对提交（评审 checklist 项）
4. **设计令牌共享**：色板 hex、间距、字号阶只定义一次（共享层），分栈构造原生 Color/Font——保证两端视觉一致性可审计
5. **文案零散布**：字符串全走 AppCore L10n 表（现状已是），双端不得新增裸字符串
6. **行为一致性测试**：共享 VM 单测在 macOS + Linux 两个 CI job 都跑（双绿），作为「双端行为一致」的强制防线；UI 壳不写平台专属测试（UISnapshotTests 保持 macOS-only）

---

## 五、构建与发布矩阵（CI / scripts 改造）

### 5.1 CI 矩阵

| job | runner | 步骤 | 产物 |
|---|---|---|---|
| test (macOS) | macos-15 | 现状保持（build + test + 0-warning + .app） | AgentKeeper.app |
| test (Linux) | ubuntu-24.04 | setup-swift（swiftly / setup-swift action，版本对齐 Swift 6.x）+ `apt libsqlite3-dev libgit? 无需` + `swift build` + `swift test`（排除 macOS 测试）+ 0-warning | — |
| release | tag 触发 | macOS job（现状）+ Linux job（下） | 见 5.2 |

### 5.2 发布产物矩阵

| 产物 | 打包方式 | 备注 |
|---|---|---|
| `AgentKeeper-app-macos.zip` | 现状 | — |
| `AgentKeeper-cli-macos.zip` | 现状 | — |
| `agentkeeper-cli-linux-ubuntu24.04.zip` | `swift build -c release --product ak --static-swift-stdlib` 后打 zip | P0 即出 |
| `agentkeeper-linux-amd64.tar.gz` | 二进制 + `.desktop` + PNG 图标 + README；AppImage 后置 | P2 |
| `agentkeeper_0.x_amd64.deb` | `DEBIAN/control` + `/usr/bin/` + `/usr/share/applications/agentkeeper.desktop` + hicolor 图标 | P2；运行时依赖写 Depends: libgtk-4-1 等（P1 定栈后确定） |

细节：
- **静态 stdlib**：Linux 侧 `--static-swift-stdlib` 免去 Swift 运行时分发；系统库（glibc、libsqlite3、GTK4）仍为运行时依赖，deb 的 Depends 声明、tar.gz 的 README 写明
- **图标资源链**：Linux 需要 PNG（hicolor 多尺寸）。现有 `scripts/gen-icon.swift` 跑在 macOS（AppKit）——在 macOS release job 里顺手产 PNG 入 `assets/`，Linux 打包只消费，不重复实现绘图
- **架构**：首发仅 amd64（GitHub runner 原生 arm64 runner 可后置加）
- **签名**：Linux 无 codesign/notarization 对应物；可选 GPG 签名 release 附件，后置

---

## 六、分阶段路线（可直接拆 OpenSpec change）

### P0 — core 可移植化 + Linux CI + CLI 上 Linux（~3-5 人日）

§3 #1–#5；ci.yml 加 ubuntu-24.04 job（测试全绿 + 0-warning）；release 加 `agentkeeper-cli-linux-*.zip`；INSTALL.md / AGENTS.md 增补 Linux 安装段。
**价值**：不改产品形态，Linux 用户先用上 ak；且把「core 平台无关」变成 CI 强制事实，防回退。

### P1 — Linux UI target PoC（~2-3 人日）

`AgentKeeperUILinux` 空壳 + SwiftCrossUI PoC：侧栏 agent 列表 + skill 表 + 详情面板最小切片，直接 import AppCore 验证集成；按 §4.3 映射表逐项打勾（重点验证：`@Observable` 接入、Animation 支持面、`.searchable` 替代实现），产出选型 design 文档。视图按 S2 形态写（VM 全放共享层），保留未来收敛到单栈的通路。

### P2 — Linux app MVP（~10-15 人日）

主窗口 + 设置 + SKILL.md 预览；xdg-open 打开文件/目录；i18n 复用 AppCore 字符串表（zh/en）；托盘若栈不支持则首发降级；`scripts/build-linux-app.sh`（tar.gz + .deb）进 CI release。

### P3 — 更新通道与分发完善（~3-5 人日）

Linux 启动时查 gh-release latest → 提示 + `xdg-open` 下载页；AppImage 化（linuxdeploy）后置；README 双平台下载矩阵 + Linux 截图。

---

## 七、风险与未决问题

| 风险 | 影响 | 缓解 |
|---|---|---|
| SwiftCrossUI 控件缺口（映射表 🟡 项：@Observable 接入 / Animation / searchable 替代） | S1 下 Linux 功能降级；不影响 macOS | PoC 验收清单先行；缺口项 UI 降级实现 |
| GNOME 裸装无托盘（Ubuntu 默认 OK） | 托盘面板不可见 | 下载页声明；首发可降级「仅主窗口」 |
| FSEvents→inotify 语义差（递归 watch、事件聚合） | 实时监听行为不一致 | 协议层统一「整批回调」语义 + 对拍测试；兜底手动刷新 |
| corelibs-foundation 与 Darwin Foundation 行为差（日期/路径/编码细节） | 隐蔽 bug | Linux CI 全量 core 测试即防线；P0 起双平台跑 |
| Linux swift-testing 执行器稳定性 | CI flake | 沿用现有 retry 模式；job 隔离 |
| UserDefaults Linux 落盘位置 | 设置迁移（极低） | P2 前实机验证；必要时换 ~/.config JSON |
| macOS 侧回归（swift-crypto 切换 / MotionPolicy 搬家） | 主平台受损 | 全量测试 + 0-warning 纪律不变；macOS CI 不动 |

---

## 八、下一步（OpenSpec 流程衔接）

1. 本报告确认后先立 change：`add-linux-core-portability`（= P0，范围明确、风险低、独立价值）
2. P1 spike 后立 change：`add-linux-app`（spec delta：app-ui 增 Linux 平台要求；design 记录 SCUI 映射表验证结果与打包矩阵）
3. 「收敛形态 S1/S2」「托盘首发形态」「deb vs AppImage 优先级」在对应 design.md 逐题向用户确认（沿用「已确认决策」惯例）
