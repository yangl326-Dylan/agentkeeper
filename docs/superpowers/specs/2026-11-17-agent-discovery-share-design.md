# Agent 可发现性分享设计（2026-11-17）

## 目标

让 AI agent 在 GitHub 上能自行发现 AgentKeeper 的 skill、`ak` CLI 与 macOS App，并知道何时、如何安全使用。

## 非目标

- 本轮不在 ClawHub / Moltbook 发帖（用户确认聚焦 GitHub）
- 不改 skill 行为语义，不改 CLI 功能

## 交付物

1. `llms.txt`（仓库根目录）：机器可读摘要——能力、安装、只读/变更命令、安全边界、链接
2. README 中英各加一个 **For AI agents** 入口，指向 `llms.txt`、`AGENTS.md` 与 skill 安装命令
3. `docs/marketing/2026-11-17-agent-discovery-share.md`：中英双语分享帖源文件（与 Discussion 正文同源）
4. GitHub Discussions「Show and tell」新帖：面向 agent 的使用入口，注明由 AI agent 代发
5. GitHub topics 补 `llms-txt`、`agent-tools`

## 事实来源

- `ak doctor` / `ak list` 实机输出（92 skills · 7 agents；`agentkeeper` 在 6 个目录被编目）
- README / AGENTS.md / INSTALL.md
- `Sources/AppCore/AKCLI.swift` 命令语义：0 成功、1 未找到/歧义、2 未知命令

## 安全边界

- 只读：`ak list`、`ak doctor`、`ak disabled`
- 变更：`ak disable` / `enable` / `remove` / `restore` / `purge` 会移动或删除文件，agent 必须先征得用户同意
- 同名副本按 sha256 追踪，禁止手工搬移；停用/恢复/合并优先走 GUI（自动快照 + 历史）

## 验收

- `llms.txt` 能被 `curl` 直接读到，内容与 CLI 实际行为一致
- README 两个语言区块都有 agent 入口，链接可达
- Discussion 发在 Show and tell，含 agent 代发备注与真实 dogfood 输出
- 新增 topics 生效
