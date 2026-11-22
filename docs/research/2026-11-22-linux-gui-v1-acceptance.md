# AgentKeeper Linux GUI v1 自验收报告

- 日期：2026-11-22
- 分支/提交：`feature/linux-core-portability` @ `48e637b`
- 范围：openspec change [`add-linux-app`](../../openspec/changes/add-linux-app/proposal.md) 任务组 3–5（Linux UI 栈 / 验收冒烟 / 打包分发）
- 验收人：开发 agent（本机自验，用户确认后合入）

## 1. 验收环境

| 项 | 值 |
| --- | --- |
| 发行版 | Ubuntu 24.04（GNOME / Wayland，X11 会话可用于自动化点击） |
| GTK | GTK3 3.24.41（Gtk3Backend）；GTK4 4.14.5（仅参与 SCUI 构建矩阵） |
| 托盘库 | libayatana-appindicator3（.so.1，dlopen 符号表加载） |
| Swift | 6.2.4 RELEASE（官方 tarball，`/mnt/data/tools/swift624`） |
| CI | PR #5：macOS 15 + Ubuntu 24.04 双平台 |

## 2. 逐项验收结果

### 2.1 构建与测试（任务 4.1）

| 检查 | 结果 |
| --- | --- |
| `swift build`（debug，含 AgentKeeperUILinux 全目标） | ✅ 0 error / **0 warning** |
| `swift build -c release --product AgentKeeper` | ✅（497s，GUI 发布二进制 43MB） |
| `swift build -c release --product ak --static-swift-stdlib` | ✅（CLI 静态二进制 87MB） |
| `swift test` | ✅ **369 tests / 97 suites 全绿**（357 基线 + 12 Linux 适配器新增） |

### 2.2 GUI 冒烟（任务 4.2）

自动化驱动：`GDK_BACKEND=x11` + `xdotool` 真实点击 + `gnome-screenshot` 截图比对。

| 场景 | 结果 | 留档 |
| --- | --- | --- |
| 启动 → 三面板渲染（侧栏/列表/详情） | ✅ 进程稳定、零 GLib critical | `docs/linux-gui-main-window.png` |
| 首扫（Scan Now 点击）→ 侧栏计数/概览卡片更新 | ✅ 与 `ak list` 数据一致（0 ↔ 0；fixture 后 1 ↔ 1） | 同上 |
| 下钻：临时 fixture skill → 列表行选中 → 详情 | ✅ 头部/作用域徽章/sha256/目录大小/操作按钮全渲染 | `docs/linux-gui-skill-detail.png` |
| 文件清单（3 条目：SKILL.md、scripts/、scripts/run.sh） | ✅ 目录符号/文件符号区分；点击定位语义接 xdg-open | 同上 |
| SKILL.md 预览（共享 MarkdownBlockParser 分级渲染） | ✅ 标题/段落/代码块渲染正常（frontmatter 原样呈现与 macOS 一致） | 同上 |
| 设置窗口：外观/语言/动效三组分段选择 + About & Updates | ✅ 点选即写回 AppSettingsStore；窗口独立开合 | `docs/linux-gui-settings.png` |
| `scripts/smoke-linux-gui.sh`（后台起 + 判活） | ✅ SMOKE-PASS | — |

期间修复的渲染缺陷（均回写 `design.md` 决策 3）：

1. **EitherView 位于 NavigationSplitView detail 槽位时 case 切换后子树不渲染**（选中 skill 详情空白；`ScrollView { Text }` 最小复现确认与内容无关）→ 结构性规避：单一稳定视图类型为根，条件分支移入 ScrollView 内部；`LinuxSkillDetailView` 重构为「父持异步状态 + `LinuxSkillDetailSections` 区块视图」。
2. **嵌套 ScrolledWindow（文件清单）渲染空白** → 去嵌套，由外层详情滚动容器统一承载。
3. **Gtk paned 压缩导致工具行竖排** → 列表列 `frame(minWidth: 340)` + 按钮 `fixedSize(horizontal:)`。
4. **分段按钮标签截断（"Engli…"）** → `LinuxSegmentedChoice` 标签 `fixedSize`。
5. **概览统计卡标题截断** → 卡片 `minWidth: 100`。
6. **设置窗口标题带省略号** → L10n 新增 `settingsWindow`（"Settings"/"设置"），窗口标题与菜单文案分离。

### 2.3 托盘（任务 3.7 / 4.3）

- **正路径实测**：`mountTray` → SNI 注册成功，`org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems` 含 `…/NotificationItem/agentkeeper_tray`（debug 版与 .deb 安装版各验一次）；菜单项（摘要/打开主窗口/立即扫描/退出）由 `TrayDescriptor` 按界面语言组装。
- **降级路径**：dlopen 失败 → `mountTray` 返回 false → 侧栏底部琥珀色界内提示（`LinuxNavigationSidebar`）；`LinuxPlatformAdapterTests` 覆盖 Mock loader 失败分支。
- **GTK 冲突决议**：PoC 期 GtkBackend(GTK4) 与 AppIndicator(GTK3) 同进程冲突（`cannot register existing type 'GtkWidget'` critical 刷屏）→ 切 **Gtk3Backend**，零冲突；唯 `createPicker` 空缺以 `LinuxSegmentedChoice`/`Menu` 等价补齐。

### 2.4 打包与安装（任务 5.1–5.3）

| 检查 | 结果 |
| --- | --- |
| `scripts/build-linux-app.sh --all`（GUI 二进制在场） | ✅ `app=1`；tar.gz 43MB / .deb 33MB |
| tar.gz 便携布局 | ✅ `ak` + `agentkeeper` + `README-linux.md`；含 GUI 时命名 `agentkeeper-gui-linux-<ver>-x86_64.tar.gz` |
| .deb control | ✅ Depends 修正为 `libsqlite3-0, libgtk-3-0, libayatana-appindicator3-1`（原 libgtk-4-1 为 GtkBackend 时代残留） |
| .deb 内容 | ✅ `/usr/bin/ak`、`/usr/bin/agentkeeper`、`agentkeeper.desktop`、hicolor 32/64/128/256 四档图标 |
| `dpkg -i` 安装 | ✅ desktop-file-utils / hicolor-icon-theme triggers 正常 |
| 安装版 GUI 冒烟 | ✅ `/usr/bin/agentkeeper` 启动、三面板渲染、托盘 SNI 注册、零 critical |
| 安装版 `ak list` | ✅ |
| `dpkg -r` 卸载 | ✅ 二进制/.desktop/图标零残留 |

### 2.5 CI（任务 5.4）

- `build-linux-cli` job 扩为 **CLI + GUI 双产物**（GUI release 构建 + 打包进 artifact），release job 下载并入 Release（`agentkeeper-gui-linux-*.tar.gz` + `agentkeeper_*.deb`）。
- macOS job 与 Linux test job 的 GTK 头文件依赖随 backend 切换改 `gtk+3` / `libgtk-3-dev`。
- PR #5 三 job（macOS / Linux test / Linux CLI+GUI artifacts）以提交 `48e637b` 触发，结果见 PR 页（本报告撰写时 in_progress）。

## 3. 与 macOS 版一致性核对（任务 4.4）

- 编目/作用域/摘要：共享 `AppEnvironment` + `NavigationModel`/`ZoneListModel`/`OverviewModel` 单一数据源；fixture 前后 GUI 与 `ak list` 输出同步（0 ↔ 1）。
- 语义差异（有意，映射表结论）：`.searchable` → 页内 TextField；`.toolbar` → 列表列工具行；`Settings` scene → 独立 `Window`；托盘 macOS 走 MenuBarExtra、Linux 走 AppIndicator。

## 4. 已知边界（v1 范围内接受）

1. `Text` 长句在详情列窄宽度下的换行依赖 `fixedSize(horizontal: false, vertical: true)` 显式声明（SCUI 截断语义）。
2. SKILL.md frontmatter 在预览中原样呈现——macOS 同行为（共享解析器一致性优先），美化留后续。
3. 托盘菜单动作可用性未做端到端点击验证（SNI 注册 + 菜单模型挂载已验；GNOME 扩展渲染属桌面环境行为）。
4. `task 2.4`（RootView 展示逻辑剥离为共享 VM）按 tasks.md 注记跳过，Linux 侧以直接消费共享模型达成等效；macOS RootView 未动。

## 5. 结论

Linux GUI v1（三面板浏览/扫描/详情/设置/托盘/打包分发）在本机 Ubuntu 24.04 全链路验收通过：构建 0 warning、369 测试全绿、GUI 冒烟与安装链路实测通过。待 PR #5 CI 三 job 全绿后即可请求用户验收合入。
