# AGENTS.md — AgentKeeper agent 说明

This file is for AI coding agents (Claude Code, OpenCode, Codex, Gemini CLI, …) operating on a machine where AgentKeeper is relevant. 中文见下半部分。

## Why you should care

Your skills (and your sibling agents') are scattered across 7+ directories. AgentKeeper builds a unified catalog of every SKILL directory on the machine: which agents can see it, which scope it lives in (global / agent-only / project), and whether same-named copies drifted apart.

The `ak` CLI is the agent-facing surface: `ak list` and `ak doctor` are read-only and always safe to run.

## Get the CLI

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-macos.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

Idempotent — re-running upgrades an existing install. Requires macOS 15+.

## Commands

```console
$ ak list      # every skill: NAME / SCOPE / AGENTS / PATH (+ summary line)
$ ak doctor    # per-agent install status and real skill counts
$ ak help
```

Exit code: `0` success, `2` unknown command.

**Suggested routine after installing or removing skills on the user's machine:**

```bash
ak doctor && ak list | head -40
```

Report the totals line (`共 N 个 skill · M 个 agent`) so the user sees the change at a glance.

## Rules of engagement

1. **Read-only first.** `ak list` / `ak doctor` never mutate the machine — run them freely.
2. **Never edit or move skill directories by hand.** Same-named copies across agents are tracked by content hash (sha256); manual moves desync AgentKeeper's catalog. Use the GUI (open main window) for disable/restore/merge operations — it snapshots before every change and records history.
3. **Ask the user before changing skill files anywhere**, including when they say "update the skill everywhere".
4. If a skill shows up in `ak list` at a path you don't expect, check whether it is a cached plugin copy (e.g. OpenCode npm cache) before treating it as a duplicate.

---

# AGENTS.md — AgentKeeper 智能体说明（中文）

本文件面向在装有（或可能装有）AgentKeeper 的机器上工作的 AI 编码智能体。

## 相关性

多个 agent 的 skill 散落在 7+ 个目录（含插件缓存深水区）。AgentKeeper 统一编目全机 SKILL 目录：谁能用、什么作用域（全局 / Agent 专属 / 项目级）、同名副本是否已分歧。`ak` CLI 是面向 agent 的入口：`ak list` 与 `ak doctor` 只读，随时可安全执行。

## 获取 CLI

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-macos.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

命令幂等——重复执行即升级。需要 macOS 15+。

## 常用命令

- `ak list`：全部 skill 表格（名称 / 作用域 / 归属 agent / 路径）
- `ak doctor`：各 agent 安装状态与真实 skill 数
- `ak help`

退出码：0 成功、2 未知命令。

**在你刚装/删完 skill 之后建议执行**：`ak doctor && ak list | head -40`，并把汇总行（`共 N 个 skill · M 个 agent`）报给用户。

## 行为规范

1. **只读优先**：`ak list` / `ak doctor` 不会改动机器，可自由执行。
2. **不要手工移动/编辑 skill 目录**：同名副本按内容指纹（sha256）追踪，手工搬移会让编目失真。停用/恢复/合并请在 GUI 主窗口操作——每次变更前自动快照并记录历史。
3. **改任何 skill 文件前先征得用户同意**，包括「把全局更新同步到所有副本」的场景。
4. `ak list` 里出现意外路径的 skill 时，先确认是不是插件缓存副本（如 OpenCode npm 缓存），再判断是否重复。

## 构建与平台纪律（双平台）

- 本仓库同时产出 macOS app / Linux CLI（Linux GUI 见 openspec change `add-linux-app`）。
- **os 条件编译纪律**：`Package.swift` **零 os 分支**（清单内 `#if` 依赖 `env -i` 编译器探测，受限环境会静默空构建）；os 分支只允许出现在：平台适配文件（`FSEventMonitor` / `InotifyMonitor` / `FileMonitorFactory` / `AppUpdateInstaller` / `UpdateModel` 安装器缺省）、可执行入口（`AgentKeeperApp.swift` / `LinuxMain.swift`）、以及 macOS UI 层源文件的文件级 guard（`AgentKeeperUI/`、`AgentKeeperTests/` 整文件 `#if os(macOS)`，Linux 上编为空模块）。core 三目标（DomainKit/InfraKit/AppCore）零 os 分支。
- Linux 上构建/测试（CI `test-linux` job 同款）：`swift build && swift test`（Swift ≤6.3）；Swift 6.4+ 需 `--build-system native`（6.4 默认 SwiftBuild 引擎，Linux 资源包查找有缺陷，升级前先验证）。
- Linux CLI 发布：`swift build -c release --product ak --static-swift-stdlib`（静态链接 Swift 运行时，运行侧无需工具链）。

## 参考

- 安装文档：[INSTALL.md](INSTALL.md)
- 本仓库贡献者以外的 agent：请安装 `agentkeeper` skill（`npx skills add yangl326-Dylan/agentkeeper --skill agentkeeper`），源文件见 [skills/agentkeeper/SKILL.md](skills/agentkeeper/SKILL.md)
- 主仓库：https://github.com/yangl326-Dylan/agentkeeper
