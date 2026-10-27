# Proposal

## Why

开发者在本机同时安装多个 AI coding agent（如 Claude Code、OpenCode），各自的 skill 分散在不同目录，无法统一查看、无法区分全局与 agent 专属、也无法安全地启用/禁用。AgentKeeper 需要一个高稳定性的地基能力：全盘扫描、统一视图与安全管理。

## What Changes

- 新增 agent 扫描能力：通过可插拔 AgentAdapter 检测本机已安装的 agent（MVP 内置 Claude Code、OpenCode），统一报告安装状态与 skill 目录。
- 新增 skill 目录与查看能力：自动发现 skill（含 SKILL.md 的目录），解析元数据（name/description），计算内容 SHA256 用于变更检测。
- 新增作用域标记：每个 skill 标记为 `agent 专属`、`共享（全局）` 或 `multi-agent 铺设`。
- 新增启用/禁用能力：通过原子化目录搬移实现禁用/启用，带 manifest 回溯与冲突保护，失败自动回滚。
- 新增本地版本快照能力：AgentKeeper 自行在后台对 skill 变更做自动快照（记录历史 diff 支持查看），若 skill 来自 git 仓库则同时读取 git 历史展示。
- 新增应用 UI 壳：主窗口采用三面板布局（agent/skill 导航树 → skill 列表 → 详情/文件视图），并常驻菜单栏（MenuBar Extra）显示 agent/skill 状态与快捷入口。
- 实时刷新：使用 FSEvents 监听 skill 目录，外部修改后自动增量重扫描并更新 UI。
- 技术栈：Swift 6 + SwiftUI（主体与动效）+ AppKit 桥接（复杂视图），目标 macOS 14+，架构为「文件系统为主真相 + SQLite 缓存索引」。
- **明确不在本变更范围**（后续独立变更）：跨 agent skill 复制/同步、git/市场安装、内容风险扫描引擎、skill 内置编辑器。

## Capabilities

### New Capabilities

- `agent-discovery`: 检测本机已安装 agent、枚举其配置与 skill 根目录（AgentAdapter 注册表、扫描调度）。
- `skill-catalog`: 发现/解析/索引 skill，标记作用域（全局 vs agent 专属），提供统一查询与视图数据。
- `skill-lifecycle`: skill 的启用/禁用与文件安全操作（原子搬移、manifest、冲突检测、失败回滚）。
- `skill-snapshots`: skill 内容变更的本地自动快照、历史记录查看、恢复旧版本；git 仓库来源的历史读取。
- `app-ui`: 应用壳与主交互：三面板主窗口、菜单栏常驻、动效规范、扫描状态与刷新反馈。

### Modified Capabilities

（无——本项目为全新项目。）

## Impact

- **代码**：全新 Swift 项目（crate 无）。目录：`AgentKeeper/`（App）、`DomainKit/`（模型）、`InfraKit/`（扫描器/索引/监控/快照）。
- **依赖**：Swift 6 toolchain；SQLite（系统 libsqlite3 + 轻封装）；git 操作通过系统 `git` 命令行先实现（MVP 不引 libgit2）。
- **系统**：写入 `~/.agentkeeper/`（禁用区、快照存储、缓存索引）；需 FSEvents 与用户授权的 `~/.claude` 等目录读权限（沙盒策略：MVP 首选非沙盒 + Developer ID 分发路径，规避 full disk access 摩擦，审核确认后记录于 design.md）。
- **兼容性风险**：agent 目录结构随版本变化 → adapter 全部版本化声明 + 未知结构降级为「无法识别」而非错误。
