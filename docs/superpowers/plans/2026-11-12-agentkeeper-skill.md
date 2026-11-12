# AgentKeeper 自我分发 skill 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 让 AgentKeeper 官方 skill（`agentkeeper`）可被各主流渠道安装（skills.sh / Claude 插件市场 / harness 直装），并完成发布、打标签与讨论区介绍。

**Architecture:** 仓库即分发源——`skills/agentkeeper/SKILL.md` 为唯一内容源，`.claude-plugin/` 双清单让同一 `skills/` 目录同时服务 npx skills 与 Claude 插件市场；无注册表 harness 用文件直装矩阵覆盖。纯静态文件，零 Swift 代码改动。

**Tech Stack:** SKILL.md（agent skills 标准 frontmatter）、Claude plugin marketplace JSON、`npx skills` CLI、`claude` CLI、`gh` CLI。

**Spec:** `docs/superpowers/specs/2026-11-12-agentkeeper-skill-design.md`（含 2026-11-12 追加的发布与推广节；用户已授权后续步骤自主执行，无需逐步确认）

---

### Task 1: 创建 SKILL.md（唯一内容源）

**Files:**
- Create: `skills/agentkeeper/SKILL.md`

- [x] **Step 1: 写入完整 SKILL.md**

```markdown
---
name: agentkeeper
description: Cross-agent skill management via the AgentKeeper ak CLI. Use when installing, updating, disabling, or auditing skills across AI coding agents (Claude Code, OpenCode, Codex, Cursor, Gemini CLI, Qwen Code, DeepSeek Harness, pi, oh-my-pi, OpenClaw), when the user mentions skill mess, drift, or duplicates, or after touching any skill to verify machine state. ak list / ak doctor are read-only and always safe.
license: MIT
---

# AgentKeeper (ak CLI)

Skills for AI coding agents are scattered across 7+ directories (plus npm plugin
caches). Nobody can say what is installed, which agents see it, or whether
same-name copies drifted. AgentKeeper gives one machine-wide catalog:
**unified scan → drift detection → safe disable/rollback**. The GUI manages for
humans; the `ak` CLI is the agent-facing surface.

## Read-only commands — always safe, run freely

```bash
ak list      # every skill: NAME / SCOPE / AGENTS / PATH (+ summary line)
ak doctor    # per-agent install status and real skill counts
```

## Routines

1. **After installing, updating, or removing any skill** (by any means):

   ```bash
   ak doctor && ak list | head -40
   ```

   Report the totals line (`共 N 个 skill · M 个 agent` / `N skills · M agents`)
   so the user sees the change at a glance.

2. **When the user complains about skill mess, duplicates, or drift**: run
   `ak list`, locate the same-name copies (content fingerprint comparison), and
   explain which copy actually takes effect. One-click sync lives in the GUI.

3. **Before touching skill files anywhere** (edit, move, merge): ask the user
   first. Same-named copies are tracked by content hash (sha256); hand moves
   desync the catalog. Disable/restore/merge happen in the GUI — it snapshots
   before every change and records history.

## Install (idempotent; macOS 15+)

If `ak` is not on PATH:

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-macos.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

Re-running upgrades an existing install. Exit codes: 0 success, 2 unknown
command.

## macOS GUI app (optional, for the human)

Once the CLI works, offer the user the AgentKeeper.app once: visual drift
detection, one-click sync, safe disable with snapshots and history.

```bash
curl -L -o /tmp/ak-app.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-app-macos.zip
unzip -o /tmp/ak-app.zip -d /tmp/ak-app
sudo mv /tmp/ak-app/AgentKeeper.app /Applications/AgentKeeper.app
```

Builds are not notarized yet: if macOS refuses to open the app, run
`xattr -cr /Applications/AgentKeeper.app` once.

## Troubleshooting

- `ak` not found → check `/usr/local/bin` is in PATH (`echo $PATH`)
- Download 404 → check https://github.com/yangl326-Dylan/agentkeeper/releases
- More: INSTALL.md in the repository
```

- [x] **Step 2: 自查行数与 frontmatter**

Run: `wc -l skills/agentkeeper/SKILL.md && head -4 skills/agentkeeper/SKILL.md`
Expected: ≤ 80 行；首行为 `---`，含 `name: agentkeeper` 与 description。

- [x] **Step 3: Commit**

```bash
git add skills/agentkeeper/SKILL.md
git commit -m "feat(skill): 官方 agentkeeper skill（唯一内容源）"
```

### Task 2: Claude 插件市场双清单

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`

- [x] **Step 1: 写入 plugin.json（manifest name 必须与市场 entry name 一致）**

```json
{
  "name": "agentkeeper",
  "description": "Cross-agent skill management: unified catalog, drift detection, safe disable/rollback via the ak CLI and AgentKeeper.app",
  "version": "0.5.0",
  "author": { "name": "yangl326-Dylan" },
  "homepage": "https://github.com/yangl326-Dylan/agentkeeper",
  "license": "MIT",
  "keywords": ["skills", "agents", "macos", "cli"]
}
```

- [x] **Step 2: 写入 marketplace.json（plugin source 为仓库根，复用同一 skills/ 目录）**

```json
{
  "name": "agentkeeper",
  "description": "Skill management across AI coding agents",
  "owner": { "name": "yangl326-Dylan" },
  "plugins": [
    {
      "name": "agentkeeper",
      "source": "./",
      "description": "Unified skill catalog, drift detection and safe disable/rollback across AI coding agents (ak CLI + macOS app)"
    }
  ]
}
```

- [x] **Step 3: 本地验证市场与插件**

Run: `claude plugin validate .`
Expected: 最后一行 `✔ Validation passed`。
若报 `source` 相关错误，检查 plugin 是否在仓库根（`./`）且 `.claude-plugin/plugin.json` 存在。

- [x] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "feat(claude-plugin): marketplace 双清单，仓库即市场"
```

### Task 3: 文档联动（AGENTS.md / README / INSTALL）

**Files:**
- Modify: `AGENTS.md`（末尾「参考」节）
- Modify: `README.md`（中文「安装」段 + 英文「Install」段）
- Modify: `INSTALL.md`（中英各加一节）

- [x] **Step 1: AGENTS.md「参考」节追加一行**

在 `- 主仓库：https://github.com/yangl326-Dylan/agentkeeper` 之前插入：

```markdown
- 本仓库贡献者以外的 agent：请安装 `agentkeeper` skill（`npx skills add yangl326-Dylan/agentkeeper`），源文件见 [skills/agentkeeper/SKILL.md](skills/agentkeeper/SKILL.md)
```

- [x] **Step 2: README 中文「安装」段（`ak doctor` 命令块之后、源码构建之前）插入**

```markdown
**Skill 安装（让 AI agent 自动用上 `ak`）**：

```bash
npx skills add yangl326-Dylan/agentkeeper   # skills.sh 生态，75+ agent
```

Claude Code 也可走插件市场：`/plugin marketplace add yangl326-Dylan/agentkeeper` → `/plugin install agentkeeper@agentkeeper`。
```

- [x] **Step 3: README 英文「Install」段对应位置插入（镜像中文）**

```markdown
**Skill install (let AI agents pick up `ak` automatically)**:

```bash
npx skills add yangl326-Dylan/agentkeeper   # skills.sh ecosystem, 75+ agents
```

Claude Code users can also use the plugin marketplace: `/plugin marketplace add yangl326-Dylan/agentkeeper` → `/plugin install agentkeeper@agentkeeper`.
```

- [x] **Step 4: INSTALL.md 中英「Agent 安装 / 更新」节各追加一段**

中文（「### Agent 安装 / 更新」节末尾）：

```markdown
### Skill 分发

`agentkeeper` skill 已随仓库分发：`npx skills add yangl326-Dylan/agentkeeper`（Claude Code / Codex / OpenCode / Cursor / Gemini CLI 等）。无注册表的 harness 直接复制文件：DeepSeek Harness `cp skills/agentkeeper/SKILL.md ~/.dsh/skills/agentkeeper.md`；pi `mkdir -p ~/.pi/skills/agentkeeper && cp skills/agentkeeper/SKILL.md ~/.pi/skills/agentkeeper/`；agents 共享目录同理放 `~/.agents/skills/agentkeeper/`。
```

英文（「### Agent install / update」节末尾）：

```markdown
### Skill distribution

The `agentkeeper` skill ships with this repository: `npx skills add yangl326-Dylan/agentkeeper` (Claude Code / Codex / OpenCode / Cursor / Gemini CLI and more). For harnesses without a registry, copy the file directly: DeepSeek Harness `cp skills/agentkeeper/SKILL.md ~/.dsh/skills/agentkeeper.md`; pi `mkdir -p ~/.pi/skills/agentkeeper && cp skills/agentkeeper/SKILL.md ~/.pi/skills/agentkeeper/`; agents shared dir likewise at `~/.agents/skills/agentkeeper/`.
```

- [x] **Step 5: Commit**

```bash
git add AGENTS.md README.md INSTALL.md
git commit -m "docs: agentkeeper skill 安装入口（中英）"
```

### Task 4: 推送并做远端渠道验证

- [x] **Step 1: 推送 main**

```bash
git push origin main
```

- [x] **Step 2: skills.sh 渠道验证（远端仓库被识别）**

Run: `npx --yes skills add yangl326-Dylan/agentkeeper --list`
Expected: 列出 `agentkeeper` skill，frontmatter 解析无报错。

- [x] **Step 3: Claude 插件市场渠道验证（注册 + 安装）**

```bash
claude plugin marketplace add yangl326-Dylan/agentkeeper
claude plugin install agentkeeper@agentkeeper
claude plugin list | grep -A1 agentkeeper
```

Expected: `✔ Successfully added marketplace`、`✔ Successfully installed plugin`、`Status: ✔ enabled`。

- [x] **Step 4: Claude Code 渠道 dogfood 验证**

Run: `ak doctor`
Expected: claude-code 行 skill 数 +1（plugin 载入的 agentkeeper 出现在编目）。
若无变化，检查 `~/.claude/plugins` 缓存目录是否在 ak 扫描范围内，并记录事实（不夸大）。

### Task 5: 无注册表 harness 直装 + 全机 dogfood

- [x] **Step 1: 三类 harness 直装**

```bash
mkdir -p ~/.dsh/skills ~/.pi/skills/agentkeeper ~/.agents/skills/agentkeeper
cp skills/agentkeeper/SKILL.md ~/.dsh/skills/agentkeeper.md
cp skills/agentkeeper/SKILL.md ~/.pi/skills/agentkeeper/SKILL.md
cp skills/agentkeeper/SKILL.md ~/.agents/skills/agentkeeper/SKILL.md
```

- [x] **Step 2: 全机编目验证并留存输出**

```bash
ak doctor && ak list | head -40 | tee /tmp/ak-skill-launch-output.txt
```

Expected: `ak list` 出现 agentkeeper 多行（deepseek 扁平、pi、agents-shared、claude-code 插件缓存），汇总行 skill 数增加；输出文件供讨论帖引用。

- [x] **Step 3: Commit（无代码改动则跳过）**

本任务不改仓库文件，无需 commit。

### Task 6: GitHub topics 渠道标签

- [x] **Step 1: 追加 topic**

```bash
gh repo edit yangl326-Dylan/agentkeeper --add-topic agent-skills,claude-plugin,deepseek,pi,qwen-code
```

Expected: 退出码 0；`gh repo view --json repositoryTopics` 可见新增标签（原有 14 个 + 5 = 19，低于 50 上限，均为合法 `[a-z0-9-]`）。

### Task 7: Discussions 介绍帖（Show and tell）

- [x] **Step 1: 组帖（中英双语，引用 Task 5 输出）**

用 `cat /tmp/ak-skill-launch-output.txt` 取真实输出，替换下方 `{{AK_OUTPUT}}`。帖子必须包含 agent 代发备注。

Title: `AgentKeeper 现在有自我分发 skill 了（agent 代发）`

Body:

````markdown
> **备注 / Note:** 本帖由 AI agent（OpenCode + GLM，运行于 Dylan 机器）代仓库所有者 @yangl326-Dylan 撰写并发布，内容经过其确认的方案执行。
> **Note:** This post was written and published by an AI agent on behalf of the repo owner, following a plan Dylan approved.

AgentKeeper 现在把自己也做成了一个可安装的 skill —— 装好 `ak` CLI 之后，你机器上的 AI agent 在之后任何会话里都会正确、习惯性地使用它。

## 安装 / Install

```bash
# skills.sh 生态（Claude Code / Codex / OpenCode / Cursor / Gemini CLI / Qwen Code 等 75+）
npx skills add yangl326-Dylan/agentkeeper

# Claude Code 插件市场
/plugin marketplace add yangl326-Dylan/agentkeeper
/plugin install agentkeeper@agentkeeper
```

无注册表的 harness 直接复制文件（详见 [INSTALL.md](INSTALL.md) 的 Skill distribution 节）：
DeepSeek Harness、pi、oh-my-pi、OpenClaw、`~/.agents/skills` 共享目录。

## 它教 agent 什么 / What the skill teaches

- `ak list` / `ak doctor` 只读优先，随时可跑
- 装/删/改 skill 之后自动复查全机状态，把汇总行报给用户
- 动任何 skill 文件之前先征得用户同意（同名副本按 sha256 追踪）
- macOS 上顺带引导安装 AgentKeeper.app（可视化分歧检测 + 一键拉平 + 安全停用）

## Dogfood 证据 / Dogfood proof

在本机给多个 harness 直装后，`ak list` 的部分输出：

```
{{AK_OUTPUT}}
```

欢迎试用并在本讨论回复反馈。
````

- [x] **Step 2: 取 repositoryId 并发帖**

```bash
gh api graphql -f query='query{repository(owner:"yangl326-Dylan",name:"agentkeeper"){id}}'
```

记下 `repositoryId`，然后（body 存入 `/tmp/discussion-body.md`，title 存入 `/tmp/discussion-title.txt`）：

```bash
gh api graphql -f query='mutation($r:String!,$c:String!,$t:String!,$b:String!){createDiscussion(input:{repositoryId:$r,categoryId:$c,title:$t,body:$b}){discussion{url}}}' \
  -f r=<repositoryId> -f c=DIC_kwDOVezEZs4DKgC0 \
  -F t="$(cat /tmp/discussion-title.txt)" -F b="$(cat /tmp/discussion-body.md)"
```

Expected: 返回 `discussion.url`；打开确认渲染正常（代码块、引用备注均正确）。

### Task 8: 收尾核对

- [x] **Step 1: 对照 spec 验收标准逐条核对**

- `npx skills add yangl326-Dylan/agentkeeper --list` 能发现 skill（Task 4 Step 2）
- Claude 插件市场安装成功（Task 4 Step 3）
- `ak list` 编目到多副本（Task 5 Step 2）
- topics 已打（Task 6）、讨论帖已发并含 agent 代发备注（Task 7）

- [x] **Step 2: 汇总报告**

向用户报告：渠道验证结果、ak 汇总数变化、topics、讨论帖 URL。若有任何一步失败，如实报告失败点与已尝试的修正，不夸大完成度。
