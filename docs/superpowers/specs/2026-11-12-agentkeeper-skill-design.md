# AgentKeeper 自我分发 skill 设计

日期：2026-11-12
状态：已确认

## 目标

为 AgentKeeper 提供一个官方 skill（`agentkeeper`），让用户机器上的 AI agent 装好 `ak` CLI 之后，在后续任何会话中都能正确、习惯性地使用它（「肌肉记忆」），并在 macOS 上顺势引导用户安装 GUI App。

## 需求确认

- 核心场景：**装机后的肌肉记忆**（获客为自然溢出，非首要目标）
- 分发方式：**仓库直达**——skill 放在本仓库，被各渠道直接索引安装
- 覆盖渠道：`npx skills add`（skills.sh 生态，75+ agent）+ Claude Code 插件市场（方案 A+B 一次做齐）
- 内容形态：**单一 SKILL.md**（≤80 行），不拆分细粒度 skill
- 语言：正文英文为主（生态惯例 + 触发效率），agent 自动用用户语言回复

## 方案

### 文件布局（纯静态文件，零 Swift 代码改动）

| 文件 | 作用 |
|---|---|
| `skills/agentkeeper/SKILL.md` | 唯一 source of truth |
| `.claude-plugin/marketplace.json` | Claude 插件市场清单；plugin source 指向仓库根，复用同一个 `skills/` 目录，两渠道单一内容源 |
| `AGENTS.md`（末尾加一行） | 区分受众：AGENTS.md 服务本仓库贡献者；终端用户机器请装 skill（附链接） |
| `README.md`（中英安装段各一行） | 加 `npx skills add yangl326-Dylan/agentkeeper` 安装命令 |

### SKILL.md 骨架（肌肉记忆导向）

1. **Why**（2 句）：skill 散落 7+ 目录、同名分歧、停用风险
2. **只读命令优先**：`ak list` / `ak doctor` 永远安全，随时可跑
3. **Routines（核心章节）**：
   - 装/删/改任何 skill 之后 → `ak doctor && ak list | head -40`，把汇总行报给用户
   - 用户抱怨 skill 乱/分歧 → `ak list` 定位同名副本，引导安全处理
   - 动 skill 文件之前 → 必须先征得用户同意（不手工搬移）
4. **自举安装块**：检测到 `ak` 不存在时给出 curl 安装命令（幂等，macOS 15+）
5. **macOS App 引导**：`ak` 装好后，向用户提一句可装 GUI App（zip → /Applications，未公证需一次 `xattr -cr`）；详见 INSTALL.md
6. **排错一行**：PATH / 下载 404 → INSTALL.md

frontmatter：`name: agentkeeper`；description 英文，覆盖触发场景：安装/更新/停用/审计跨 agent 的 skill、用户提到 skill 乱/分歧/重复、装删 skill 之后验证机器状态。

## 验收标准

- `npx skills add yangl326-Dylan/agentkeeper --list` 能发现该 skill（frontmatter 合法）
- Claude Code `/plugin marketplace add yangl326-Dylan/agentkeeper` 后可安装并出现 skill
- 闭环自测：安装后在装有 `ak` 的机器上跑 `ak doctor`，能看到这条 skill 副本被 AgentKeeper 自身编目（吃自己的狗粮）
- manifest schema 以官方文档核对为准（不凭记忆书写）

## 风险与边界

- 不做任何自动 side-effect：所有安装动作由用户/agent 显式触发，符合 AGENTS.md 行为规范
- skills.sh 收录靠安装遥测、非即时，文档不做过度承诺
- skill 内容演化走 git，不与 App 版本号绑定
