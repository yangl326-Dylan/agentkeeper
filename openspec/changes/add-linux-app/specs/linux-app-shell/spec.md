# Spec Delta

## Purpose

定义 AgentKeeper Linux 版应用外壳与分发行为：主窗口/设置在 Ubuntu 的可用性、系统托盘常驻入口（含降级）、文件与目录的原生打开、安装形态与更新提示。macOS 行为由既有能力覆盖，本能力只拥有 Linux 侧外壳。

## ADDED Requirements

### Requirement: Linux 主窗口可用
Linux 版 SHALL 提供与 macOS 对等的主窗口能力：三面板布局（导航/列表/详情）、SKILL.md 预览、按 agent/作用域筛选与搜索，数据与行为由共享层驱动并 MUST 与 macOS 版语义一致。

#### Scenario: Ubuntu 桌面运行
- **WHEN** 用户在 Ubuntu 24.04 (GNOME) 启动 AgentKeeper
- **THEN** 主窗口呈现三面板布局并完成首次扫描，列表与详情数据与 macOS 版对同一目录的产出一致

#### Scenario: SKILL.md 预览一致
- **WHEN** 用户在 Linux 版选择某 skill 查看详情
- **THEN** SKILL.md 渲染、元数据、文件列表与 macOS 版同一 skill 的详情内容一致

### Requirement: Linux 设置窗口
Linux 版 SHALL 提供设置窗口，承载与 macOS 版同一份设置项（语言、主题等），设置值 MUST 与 macOS 版共享同一持久化语义。

#### Scenario: 语言切换生效
- **WHEN** 用户在 Linux 设置窗口切换语言
- **THEN** 界面文案即时切换，重启后保持

### Requirement: Linux 托盘常驻入口与降级
Linux 版 SHALL 通过系统托盘规范（StatusNotifierItem/AppIndicator）提供常驻入口，展示摘要与快速入口（打开主窗口、立即扫描），行为对齐 macOS 菜单栏面板语义；当桌面环境不支持托盘时 SHALL 降级为仅主窗口运行并 MUST 在界内提示原因，MUST NOT 崩溃或静默失效。

#### Scenario: Ubuntu 托盘可用
- **WHEN** 用户在 Ubuntu 24.04（默认支持 AppIndicator）启动应用
- **THEN** 托盘图标出现，点击展开摘要面板，可触发打开主窗口与立即扫描

#### Scenario: 托盘不可用降级
- **WHEN** 桌面环境无 StatusNotifierItem 支持（如 GNOME 裸装未装扩展）
- **THEN** 应用正常启动并仅提供主窗口，界内可见「托盘不可用」提示与解决指引

### Requirement: Linux 文件与目录打开
Linux 版 SHALL 通过平台机制打开文件与目录（文件用系统默认应用、目录用文件管理器并支持定位），替代 macOS 的 Finder 语义。

#### Scenario: 打开 skill 所在目录
- **WHEN** 用户对某 skill 触发「在文件管理器中显示」
- **THEN** 系统文件管理器打开该目录并定位到该条目（不支持定位时至少打开父目录）

### Requirement: Linux 安装形态与更新提示
Linux 版 SHALL 以 .deb 与 tar.gz 两种形态分发（含 .desktop 桌面条目与图标），应用内 SHALL 提供更新检查提示（查 GitHub Release 最新版并打开下载页）；更新 MUST NOT 静默自安装。

#### Scenario: .deb 安装后桌面可发现
- **WHEN** 用户 `apt install` 该 .deb 后在 GNOME 活动概览搜索 AgentKeeper
- **THEN** 应用图标与桌面条目可见，点击启动正常

#### Scenario: 更新提示
- **WHEN** 线上存在比当前版本更新的 Release
- **THEN** 应用在设置或界面提示新版本并提供跳转下载页的入口
