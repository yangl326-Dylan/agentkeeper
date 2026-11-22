# Tasks

## 1. PoC 验证（首任务，定 🟡 项）

- [x] 1.1 安装 GTK4 运行/开发库（libgtk-4-dev 4.14.5）；引入 SwiftCrossUI（锁定 from: 0.11.0）；最小 App 本机跑通（窗口真实渲染，进程稳定）
- [x] 1.2 验证映射表 🟡 项：@Observable 接入 ✅（@State 持有外部类 + $ 绑定直通）、TextField 过滤 ✅、基础控件/布局 ✅；Animation/Commands/NavigationSplitView/Table 留实装时验证（官方示例佐证存在）；结论已回写 design.md 决策 3

## 2. 共享展示层（薄壳化准备）

- [x] 2.1 新建 `AgentKeeperShared` target；移入 AppSettingsStore、ZoneModels、SidebarAgentModel、SkillPreviewModel（纯移动，AgentKeeperUI 转发引用）
- [x] 2.2 移入 AppEnvironment（PlatformAdapter 注入 reduceMotion 等探测）；macOS 实现适配器
- [x] 2.3 移入 Markdown 块解析 + ClaudePalette 令牌（hex/间距/字号阶）；`Color` 构造分栈
  - 注：Markdown 块解析已完成（`MarkdownBlockParser.swift` 入 Shared，渲染留 UI 层）；ClaudePalette 令牌暂留 UI 层，随 Linux 令牌任务后置；另随行移入 OverviewModel（AppEnvironment.overviewModel 签名所需）
- [ ] 2.4 从 RootView 剥离展示逻辑为共享 ViewModel（行构建/过滤/排序/状态文案）；共享 VM 单测
  - 注：本次跳过（风险高），留给后续小步 PR
- [x] 2.5 PlatformAdapter 协议 + macOS 实现（reveal/openURL/chooseDirectory/activate/terminate）

## 3. Linux UI 栈

- [x] 3.1 `AgentKeeperUILinux` target + SCUI App 入口；`AgentKeeper` @main `#if os` 装配
  - 注：backend 实装为 **Gtk3Backend**（决策 3 的 GtkBackend/GTK4 在实装中发现与 AppIndicator GTK3 同进程类型注册冲突：`cannot register existing type 'GtkWidget'` critical 刷屏；Gtk3Backend 功能覆盖本应用全部所需，唯 Picker 未实现 → 自绘 `LinuxSegmentedChoice` + `Menu` 等价表达）；托盘 dlopen libayatana-appindicator3 与 GTK3 同栈零冲突
- [x] 3.2 LinuxRootView（三面板映射 SCUI 布局：侧栏/列表/详情）
  - 注：NavigationSplitView 三列 + 列表列 minWidth 340（Gtk paned 默认压缩会把工具行挤成竖排，实装截图验证）
- [x] 3.3 列表 + TextField 过滤（同一共享 VM）+ 状态语义（颜色/图标映射共享令牌）
  - 注：过滤/行模型直接消费 AppEnvironment + NavigationModel 共享逻辑；agent 切换以 Menu 表达（无 Picker）
- [x] 3.4 详情面板：元数据/文件列表/SKILL.md 渲染（共享解析 + SCUI 呈现）
  - 注：结构纪律——if/else 条件分支必须放在 ScrollView **内部**（EitherView 位于分栏 detail 槽位时 case 切换后弹性尺寸子树不渲染，SCUI Gtk3Backend 实测；已回写 design.md）；文件清单不用嵌套 ScrolledWindow（同类渲染不稳），由外层统一滚动
- [x] 3.5 Linux 设置窗口（独立 WindowGroup）：语言/主题，同一 AppSettingsStore
  - 注：外观/语言/动效三组 `LinuxSegmentedChoice`（自绘分段选择）+ About & Updates（UpdateModel 直用）
- [x] 3.6 Linux PlatformAdapter 实现：xdg-open 打开文件/目录、更新检查提示（gh-release 查询 + 跳下载页）
  - 注：xdg-open 参数单测覆盖（绝对 URL 语义）；更新检查走共享 UpdateModel + `openURL` 跳 Release 页
- [x] 3.7 托盘：AppIndicator/DBus 注册 + 菜单（摘要/打开主窗口/立即扫描/退出）；注册失败降级 + 界内提示
  - 注：libayatana-appindicator3 经 dlopen 符号表（无硬链接依赖）；本机 GNOME 实测 SNI 注册成功（`RegisteredStatusNotifierItems` 含 `agentkeeper_tray`）；降级路径单测 + 界内琥珀色提示（侧栏底部）
- [x] 3.8 扫描进行中指示 + 减少动效尊重（GTK 质感，克制动效）
  - 注：工具行按钮扫描中变「正在扫描…」并禁用 + 底部状态条；`linuxMotionPolicy` 统一裁决加载占位（spinner ↔ 静态符号）

## 4. 验收与冒烟（Ubuntu 24.04 本机）

- [x] 4.1 `swift build`（含 Linux UI target）0-warning；core + 共享层测试全绿
  - 注：Swift 6.2.4 本机 0 error 0 warning；369 tests / 97 suites 全绿（357 基线 + 12 Linux 适配器）
- [x] 4.2 GUI 冒烟：启动 → 首扫 → 下钻浏览 → 过滤 → 详情预览 → 设置切换语言；截图留档
  - 注：临时 fixture skill 实测列表/详情/文件清单/markdown 预览/操作按钮（`docs/linux-gui-main-window.png`、`docs/linux-gui-skill-detail.png`、`docs/linux-gui-settings.png`）；`scripts/smoke-linux-gui.sh` 判活冒烟
- [x] 4.3 托盘正向或降级路径按本机桌面环境实测；界内提示文案确认
  - 注：正向实测（SNI 注册项含 agentkeeper_tray）；降级为单测 + dlopen 失败路径保证
- [x] 4.4 与 macOS 版行为一致性核对：同一目录的编目/作用域/摘要数据一致（共享 VM 保证，抽查比对）
  - 注：fixture 前后 GUI 列表/概览计数与 `ak list` 输出一致（0 ↔ 1 同步）；共享 AppEnvironment/NavigationModel 单一数据源

## 5. 打包与分发

- [x] 5.1 `scripts/build-linux-app.sh`：tar.gz（便携布局 + README）；.deb（control + .desktop + hicolor 图标 + /usr/bin）
  - 注：GUI 二进制存在时自动入包（`app=1`，deb 33MB / tar 43MB）；Depends 修正为 `libgtk-3-0, libayatana-appindicator3-1`（Gtk3Backend 实装后）
- [x] 5.2 图标资产：hicolor PNG 入 `assets/icons/`（macOS release job 生成或一次性入库）
  - 注：32/64/128/256 四档一次性入库；.deb 打包循环装四档 hicolor
- [x] 5.3 本机实测 `apt install` .deb → GNOME 搜索可见 → 启动正常 → 卸载干净
  - 注：`dpkg -i` 后 /usr/bin 双二进制 + .desktop + 四档图标就位；安装版 GUI 启动/托盘注册冒烟通过；`dpkg -r` 卸载零残留
- [ ] 5.4 ci.yml：Linux app 产物进 release；README 下载矩阵 + 托盘环境声明；INSTALL.md Linux GUI 安装段
  - 注：ci.yml `build-linux-cli` 产物进 release 已完成；README GUI 下载矩阵与 INSTALL.md Linux GUI 段待本 PR 收尾
