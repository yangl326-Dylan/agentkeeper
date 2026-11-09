# Skill 管理痛点分析（GitHub 社区，2026-05 ~ 2026-11）

日期：2026-11-09 · 方法：Step1 模型框架 → web-search-agent 近 6 个月证据补充 → 决策矩阵
用途：决定 AgentKeeper 下一阶段产品方向（v1.5 排期 + 定位叙事）

## 背景

上轮调研（2026-11-08）已把高热度 issue 映射为 Roadmap，并交付健康检查 v1。本轮把镜头对准「skill 管理本身」，发现**上一轮的证据边界被 2026 下半年的新证据重新划过**：真正的高频高杀伤故障是「静默失败」（遮蔽、静默截断、无提示不触发），而非显式报错类。

## 决策矩阵

 Legend：AK = AgentKeeper。🟢 已覆盖 / 🟡 部分 / 🔴 未覆盖

### 1. 同名冲突与静默遮蔽 — 🟡 → 新机会 #1

| 字段 | 内容 |
|---|---|
| evidence | claude-code#25209（项目级与全局同名遮蔽语义不透明）、mattpocock/skills#483（`code-review` 与内置冲突，两者不可兼得）、claude-code#66352（`~/.agents/skills` 与项目级优先级）；学术：arXiv 2610.11647《One Skill Too Many》——同类不同 scope 决定「覆盖或双列」，**任务照常通过但被覆盖技能的关键规则悄然失效** |
| user_voice | r/ClaudeAI 1rxjyex：用户自建冲突检测工具 + 依赖可视化；「被'删除一个自以为没用的 skill'坑过——另两个 skill 引用它，直到 agent 报错才发现」 |
| job_gap | 用户无法回答「目录里这么多 skill，**实际生效的是哪一个**」 |
| ak_status | 🔴 UI 未暴露生效优先级；但跨 agent 编目 + scope 判定（agentOnly/multiAgent/project）基础设施全在——**只差最后一层"谁真正生效"的可视化** |
| product_move | 「生效关系」区块/筛选：同名多副本时标注当前 scope 优先级下哪个生效、哪些被遮蔽；连带可做被删后依赖断裂提醒（原声痛点，中难度，可后置） |
| ecosystem_alt | 冲突检测多为社区脚本；管理器类产品均未做生效语义可视化 → **空白** |
| decision_hint | **做**（轻量起步）——AK 定位差异化的最佳落点 |

### 2. 清单静默截断与压缩丢失（routing 失明）— 🔴 → 新机会 #2

| 字段 | 内容 |
|---|---|
| evidence | claude-code#81081（**官方 reproduced**：36 个 skill 中 27 个在 session-start 清单降级为 name-only，无任何提示）、#31505（超过 ~28 个 skill 直接整个不可调用）、#82017+#74990（/compact 后 skill 清单整个丢失）、#63566（捆绑 skill 无条件注入 → context +77%） |
| budget_cost | 27/36 降级；>28 不可调用；+77% context |
| job_gap | 「我装的 skill 到底进了模型的菜单没有」——功能上限是客观事实 |
| ak_status | 🔴；但 AK 已有每 agent 的 skill 计数（ak doctor / 侧栏聚合） |
| product_move | 清单预算仪表（客观计数事实，非审美阈值）：面板/侧栏按 agent 显示「N 个 skill，>28 上游已证实整个不可调用」；注意与「体积零阈值」原则区分——这是**功能性硬上限** |
| ecosystem_alt | 无人做（工具端无法改上游，但可以给用户**预警**）；上游修复信号：#81081 已 reproduced，Anthropic 可能改注入策略 → 窗口期存在但不长 |
| decision_hint | **做轻量版**（徽章级提示）；不做深挖 |

### 3. 版本与漂移 — 🟡 → 既定 v1.5 优先级上调

| 字段 | 内容 |
|---|---|
| evidence | #20697（同步 skills，54 赞）；新增实证：gentle-ai#742（`~/.agents/skills` 安装器不刷新，滞留 4 月旧版本字节，**用户完全无感知**） |
| user_voice | r/ClaudeAI 1qfa4rb「is anyone else struggling to keep agent skills (in sync)」——需求标题级直接 |
| ak_status | 🟡 目录编目有 sha256/multiAgent 漂移识别，**无来源追踪与更新检查** |
| product_move | Git 来源追踪（记录 source/commit + 上游更新检查）——上轮已立项 v1.5，本轮证据把「漂移是无感知腐烂」坐实 |
| decision_hint | **做**（维持 v1.5 首位） |

### 4. 安全与供应链 — 🔴 → 换形态：来源可见性（v1.5+）

| 字段 | 内容 |
|---|---|
| evidence | 量级剧变：Snyk ToxicSkills（3984 个 skill 扫描，1467 个缺陷 = **36.8%**）、Unit42（ClawHub 隐匿恶意 skill 可绕过自动扫描）、Datadog SecurityLabs、USENIX 2026 MalSkills 论文——已从个别 issue 升级为**行业共识威胁模型** |
| ak_status | 🔴 无任何来源/信任信息；快照 + 操作历史是安全叙事的既有底座 |
| product_move | 不做内容扫描（对抗假阳性、要安全公司级投入）；做**来源可见性**：安装来源标注（git URL/本地/Copied）、来源不明警示条——正好与 Git 来源追踪同一数据底座（合并实施） |
| ecosystem_alt | 扫描类有 Snyk/Unit42 级玩家；「本地来源管理器」没人做 |
| decision_hint | **换形态做**（轻）；README/发布叙事应引用 ToxicSkills 数据（上轮已定快照安全叙事提前，本轮再获弹药） |

### 5. 生命周期卫生 + 「agent 会死」的可迁移性 — 🟡 → 启动包价值上调

| 字段 | 内容 |
|---|---|
| evidence | claude-code 2.1.319 官方承认 `.trash` 回收站无限增长（上游自己买单）、#69175（升级后自定义 skill 全变 Unknown skill）；**gemini-cli #27274：全面迁移 Antigravity——上游 agent 会换壳，用户 skill 是跨壳资产** |
| ak_status | 🟡 停用/恢复/快照/alertHistory 完整；无跨 agent 打包迁移 |
| product_move | 启动包（Roadmap 既有项）：从任意 agent 目录勾选 → 打包 → 导入另一 agent；「换壳迁移」是最硬的叙事 |
| decision_hint | **做**（v1.5~v2 顺序内维持） |

### 6. 粒度控制（disable-model-invocation 矩阵）— 🔴 → v1.5 展示型信息

| 字段 | 内容 |
|---|---|
| evidence | Codex 完全不支持该字段（mattpocock/skills#516 + 实测博客）；opencode #11972/#34498/#12109；反向坑 claude-code#79560（停用模型调用后 skill 也没法被其他 skill 组合 ⇒ workflow composition 被破坏） |
| ak_status | 🔴 未展示；健康检查有 frontmatter 完整性，字段兼容是自然延伸 |
| product_move | 详情面板「agent 支持」标记（信息展示而非功能实现）——轻量 |
| decision_hint | 排在生效关系/预算仪表之后 |

### 7. 上下文/token 膨胀（纯体积视角）— 🟢 观察

health check v1 已展示体积事实（零阈值）。#63566 的 77% 证据已并入第 2 条「routing 失明」叙事。决策：维持现状，不新增。

### 8. 触发可靠性/质检缺位 — 🔴 → **不做**（有生态竞品 + 需跑模型）

skillsaw（71★，claudelint 后继）：deterministic CLI 的 SKILL.md 评分/诊断/校验工具——**生态已有人做专门的质检工具链**；389-skill 的触发 sweep（29% 失效）证明问题真实但检验必须跑真实模型。AK 维持「展示型健康检查」，不越界。skillsaw #335 的 schema 对齐信息可白嫖进 frontmatter 兼容知识库。

### 9. 规模化收纳/registry — 🟢 维持上轮决策

skills.sh（事实入口）+ 目录站已成熟；AK 的启动包 = 轻量私有 registry 形态，不重复造市场。

### 10（新小项）. 跨 agent 目录串扰 — 🟡 → 并入 #1 生效关系

Cursor 论坛 161691：激进加载 `~/.claude/skills` 里**其他 agent** 的 skill 吃掉 50% token；gemini-cli #15895 对标准互操作存疑。AK 已能回答「这个目录被哪些 agent 加载」（多 agent 编目）——把答案在 UI 里说出来即可，**与 #1 同一工作面**。

## 方向结论（建议采纳）

**产品叙事升级**：一句话定位从「多个 agent 的 skill 管理器」聚焦为「**看不见的 skill 世界，AgentKeeper 让它可见**」——覆盖本轮全部四条新痛点（遮蔽、截断、漂移、串扰的共同解药是可见性）。

**执行排序**（健康检查 v1 已交付）：

| 优先级 | 项目 | 难度 | 理由 |
|---|---|---|---|
| #1 | 生效关系（同名遮蔽可视化 + 串扰说明） | 轻-中 | AK 差异化空白点，复用既有编目；可与健康检查 UI 语言一致 |
| #2 | Git 来源追踪 + 来源可见性（含安全叙事合并） | 轻-中 | 上轮 v1.5 既定首位，本轮证据（漂移是无感知腐烂 + 36.8% 缺陷率）双重加持 |
| 3 | 清单预算仪表（>28 硬上限提醒） | 轻 | reproduced 级客观事实，徽章实现；窗口期随上游修复关闭 |
| 4 | 启动包（跨 agent 迁移） | 中 | 「agent 换壳」叙事，Roadmap 既有 |
| 5 | 字段支持矩阵展示 | 轻 | 信息型，顺手 |

不新增：触发率质检（skillsaw）、registry/市场（skills.sh）、内容安全扫描（Snyk 级玩家）。

## 证据来源

主 issue：claude-code #81081（reproduced）/ #31505 / #82017 / #74990 / #63566 / #25209 / #66352 / #69175 / #79560；mattpocock/skills #483、#516；gentle-ai #742；gemini-cli #15895 / #16084 / #27274；opencode #11972 / #34498 / #12109。
研究与安全：Snyk ToxicSkills、Unit42 ClawHub 分析、Datadog SecurityLabs、USENIX 2026 MalSkills、arXiv 2610.11647（同装冲突）、arXiv 2603.27204（MalSkills preprint）。
社区原声：r/ClaudeCode 1s0k1vj（too many skills）、r/ClaudeAI 1qfa4rb（同步）、r/ClaudeAI 1rxjyex（冲突工具）。
生态快照：skillsaw（stbenjam）、skills.sh、mattpocock/skills（多 agent installer）、skills-hub.ai / skillsdirectory.com / ClawHub、Claude Skills Manager VSIX扩展、skillreg.dev；alirezarezvani/claude-skills 触发 sweep CHANGELOG。
