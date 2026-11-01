# AgentKeeper 开源与产品战略（design）

日期：2026-11-01 · 状态：已与 maintainer 对齐决策

## 0. 一句话定位

**跨 agent 的 skill 管理刚需工具**：你的 skill 装在哪、谁在用、版本一不一致——一屏说清，一个按钮摆平。

主心骨 = 管理/同步刚需派（非市场目录派）；目录/发现类功能只作为拉新辅助，不抢主线资源。

## 1. 已确认的四个决策

| 决策点 | 结论 |
|---|---|
| 定位 | 跨 agent 管理刚需派：主打多 agent 用户的统一目录 + 副本同步 |
| CLI | **开源之前就做**（`ak` 命令）——agent 用户活在终端，且 agent 可自行调用 CLI，是最大传播杠杆 |
| License | **MIT** |
| 商业化 | **核心管理功能永久免费，写进 README**；未来仅团队/云同步类增值收费 |

## 2. 目标用户与核心痛点

1. **多 agent 重度用户**（Claude Code + OpenCode + Codex + Cursor…）：skill 分散在 7+ 目录（含 opencode v2 npm 插件缓存这类深水区），版本漂移无人察觉。
2. **Skill 作者**：一份 skill 要铺到多个 agent，手工拷贝、改完忘了同步。
3. **团队**：新人 onboarding 需要统一 skill 集。

差异化护城河：官方管理器永远只管自家；AgentKeeper 中立跨厂商 + 文件系统即真相（无数据库黑盒）+ 安全停用/回滚（原子搬移 + manifest + 快照）。

## 3. 功能路线（按痛点强度排序）

### P0 —— 装机理由
- **Git 唯一真源**：一个仓库 → 铺到所有 agent；drift 可视化 + 一键拉平（现有 git 安装升级为持续同步闭环）。
- **CLI 伴随**：`ak list / ak install / ak sync / ak doctor`；GUI 管人，CLI 管 agent。
- **Diff 查看器**：同名安装（内容不一致）并排 diff——有 diff 才敢点「更新全部副本」。
- **启动包**：首启空目录一键装精选集，空白态直接变 wow。

### P1 —— 留住理由
- Skill 健康检查：frontmatter 缺失/描述超长/token 体积警告。
- ⌘K 全局搜索 + 空格 Quick Look。
- 批量操作（多选停用/同步/打标签）。
- 只读 skill 索引：聚合 GitHub awesome 列表，站内搜索安装（不托管）。

### P2 —— 团队/付费理由
- 团队共享 skill 集（git 协议上加组织层）、跨机同步（iCloud/git）、审计。

### 明确不做
skill 运行时、agent 编排、存储用户代码。与 agent 厂商共生而非竞争。

## 4. UI 交互方向

- **键盘优先**：⌘K、j/k 导航、空格 Quick Look（目标用户是终端人口）。
- **Drift 视觉化**：列表行红点角标，点进去直接 diff，不在详情页深处。
- **拖拽安装**：拖 skill 到侧栏 agent = 安装；拖出 = 导出（Finder 心智）。
- **菜单栏 = 被动状态**：「3 个 skill 有更新 · 2 个副本分歧」。
- **空态即教程**：无 agent 时引导安装，不出空白。

## 5. 开源执行

- MIT LICENSE + README（顶部 15 秒 GIF，中英双语）。
- 发布链路：GitHub Releases + **公证构建** + Sparkle 自动更新 + `brew install --cask agentkeeper`。
- **Adapter 即插件**：StandardAgentAdapter 的配置驱动协议文档化（声明式 JSON/YAML），社区加 agent = 10 行配置 PR，不需要会 Swift。
- 可信度资产晒出：269 TDD 测试、OpenSpec 规格、架构文档。

## 6. 运营路线与指标

| 阶段 | 时间 | 动作 | 目标 |
|---|---|---|---|
| P0 预备 | 本月 | CLI、LICENSE/README/CI（macOS runner 跑测试+公证构建）、Homebrew；V2EX/即刻/X/Show HN 发布 | 发布周 500+ star |
| P1 生态 | 1–3 月 | diff 视图、启动包、adapter 协议开放、每周 changelog | 2k star、3 外部 contributor、brew 下载 5k |
| P2 目录 | 3–6 月 | 只读 skill 索引、团队 git 同步 beta、opt-in 匿名统计 | 1w 活跃、官方文档/newsletter 提及 1 次 |
| P3 可持续 | 6–12 月+ | CLI 跨平台先行、GUI 跨平台评估、云同步/团队版收费、Sponsors | 商业化验证 |

**北极星指标**：周活跃管理的 skill 数、经 AgentKeeper 安装的 skill 次数（非 star）。

**最大风险**：官方自建管理器。对策：永远快一步支持新 agent/新格式；中立跨厂商立场；CLI 成为 agent 生态默认。

## 7. 立即行动（Phase 0 backlog）

1. `ak` CLI（executable target `ak`，复用 InfraKit/AppCore；TDD）。
2. LICENSE(MIT) + README（双语 + GIF + 「核心永久免费」承诺）。
3. CI：GitHub Actions macOS（test → build → notarize → release）。
4. Homebrew cask 提交。
5. 发布素材：15s GIF、demo 仓库。
