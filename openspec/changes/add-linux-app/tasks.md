# Tasks

## 1. PoC 验证（首任务，定 🟡 项）

- [ ] 1.1 安装 GTK4 运行/开发库（libgtk-4-dev）；引入 SwiftCrossUI（锁定版本）；最小 App 本机跑通（窗口出现）
- [ ] 1.2 验证映射表 🟡 项：@Observable 接入方式、Animation 支持面、TextField 过滤替代 .searchable、Commands 可用性；结论回写 design.md

## 2. 共享展示层（薄壳化准备）

- [ ] 2.1 新建 `AgentKeeperShared` target；移入 AppSettingsStore、ZoneModels、SidebarAgentModel、SkillPreviewModel（纯移动，AgentKeeperUI 转发引用）
- [ ] 2.2 移入 AppEnvironment（PlatformAdapter 注入 reduceMotion 等探测）；macOS 实现适配器
- [ ] 2.3 移入 Markdown 块解析 + ClaudePalette 令牌（hex/间距/字号阶）；`Color` 构造分栈
- [ ] 2.4 从 RootView 剥离展示逻辑为共享 ViewModel（行构建/过滤/排序/状态文案）；共享 VM 单测
- [ ] 2.5 PlatformAdapter 协议 + macOS 实现（reveal/openURL/chooseDirectory/activate/terminate）

## 3. Linux UI 栈

- [ ] 3.1 `AgentKeeperUILinux` target + SCUI App 入口；`AgentKeeper` @main `#if os` 装配
- [ ] 3.2 LinuxRootView（三面板映射 SCUI 布局：侧栏/列表/详情）
- [ ] 3.3 列表 + TextField 过滤（同一共享 VM）+ 状态语义（颜色/图标映射共享令牌）
- [ ] 3.4 详情面板：元数据/文件列表/SKILL.md 渲染（共享解析 + SCUI 呈现）
- [ ] 3.5 Linux 设置窗口（独立 WindowGroup）：语言/主题，同一 AppSettingsStore
- [ ] 3.6 Linux PlatformAdapter 实现：xdg-open 打开文件/目录、更新检查提示（gh-release 查询 + 跳下载页）
- [ ] 3.7 托盘：AppIndicator/DBus 注册 + 菜单（摘要/打开主窗口/立即扫描/退出）；注册失败降级 + 界内提示
- [ ] 3.8 扫描进行中指示 + 减少动效尊重（GTK 质感，克制动效）

## 4. 验收与冒烟（Ubuntu 24.04 本机）

- [ ] 4.1 `swift build`（含 Linux UI target）0-warning；core + 共享层测试全绿
- [ ] 4.2 GUI 冒烟：启动 → 首扫 → 下钻浏览 → 过滤 → 详情预览 → 设置切换语言；截图留档
- [ ] 4.3 托盘正向或降级路径按本机桌面环境实测；界内提示文案确认
- [ ] 4.4 与 macOS 版行为一致性核对：同一目录的编目/作用域/摘要数据一致（共享 VM 保证，抽查比对）

## 5. 打包与分发

- [ ] 5.1 `scripts/build-linux-app.sh`：tar.gz（便携布局 + README）；.deb（control + .desktop + hicolor 图标 + /usr/bin）
- [ ] 5.2 图标资产：hicolor PNG 入 `assets/icons/`（macOS release job 生成或一次性入库）
- [ ] 5.3 本机实测 `apt install` .deb → GNOME 搜索可见 → 启动正常 → 卸载干净
- [ ] 5.4 ci.yml：Linux app 产物进 release；README 下载矩阵 + 托盘环境声明；INSTALL.md Linux GUI 安装段
