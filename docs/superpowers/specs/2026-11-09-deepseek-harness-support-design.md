# DeepSeek Harness 支持设计

日期：2026-11-09 · 状态：已确认（用户免确认授权推进）
依据：DeepSeek Harness 官方文档 `docs/subsystems/skills`（developer preview，rank 表为权威来源）

## 目标

AgentKeeper 收录 DeepSeek Harness（`dsh`）为内置 agent；生效关系（同名遮蔽）判定同步升级。版本 **v0.5.0**（minor：新 agent + 扫描器能力扩展）。

## 官方事实（设计输入）

dsh 本地 skill 发现 rank 表（官方文档）：

| Rank | Source | Root |
|---|---|---|
| 100 | project-dsh | `<projectRoot>/.dsh/skills` |
| 200 | project-agents | `<projectRoot>/.agents/skills` |
| 300 | custom | Config.customSkillDirs |
| 400 | user-dsh | `<dshHome>/skills` |
| 500 | user-agents | `<agentsHome>/skills` |
| 600 | bundled | Config.bundledSkillDir |

- skill 形态：目录包 `<name>/SKILL.md` + 扁平 `<name>.md`（直属根目录）；嵌套递归 `**/SKILL.md` 不支持
- name 约定 kebab-case；同名优先级按 rank/提供方/本地顺序，目录包 vs 扁平的细则无文档

## 已确认决策（用户逐题确认）

1. **目录映射 B（保守）**：deepseek 只声明 `~/.dsh/skills` + 项目级 `.dsh/skills`；`~/.agents/skills`（rank 500）继续归 agents-shared，不接入——零展示变化、零回归风险，rank 500 串扰事实 v1 不可见（宁可少说）
2. **双形态支持**：目录包 + 扁平 `.md` 都扫（dsh 官方语义）；AK 只认「root 直属」扁平文件（对齐 dsh「直属平铺条目」语义）
3. **遮蔽粒度**：仅 project > user（rank 100 > 400 文档背书）；rank 100 vs 200 跨 root 排序不判

## 改动分块

### A. AgentSpec 收录（一个字面量）

```swift
public static let deepseek = AgentSpec(
    id: "deepseek",
    displayName: "DeepSeek Harness",
    detectionSubpaths: [".dsh"],
    skillRootCandidates: [".dsh/skills"],
    projectSkillSubpaths: [".dsh/skills"],
    projectRootDiscovery: .none,   // dsh 无项目注册中心；项目级仅扫已知根（claude.json + 用户手动添加）
    icon: "wand.and.stars"
)
```

追加进 `all` 末尾。`participatingAgents` 自动包含 → 已知项目根下 `.dsh/skills` 自动进扫描。

### B. 扁平 skill 扫描（唯一管线改动）

- `SkillParsing.parseFlatFile(_ file: URL) -> ParsedSkill?`：frontmatter name 缺省 = 文件名去 `.md`；files=[该文件]、totalBytes/skillMdBytes=文件大小、指纹=文件内容 sha256；空文件/编码异常 issue 同目录包语义
- `SkillCollector.collectRecursive`：非目录条目在 **root 直属层** 且后缀 `.md` → 收集（对齐 dsh「直属平铺」）；子目录内扁平文件不收（非 dsh 语义）
- DomainKit `Skill` 新增 `layout` 字段：`SkillLayout.directoryPackage`（默认）/ `.flatFile`——decodeIfPresent 兼容（同 shadowedBy 模式）。用途：UI 操作降级 + 未来区分形态
- **v1 扁平 skill 只读**：停用/回收站/分发/安装到其他 agent 全部禁用（distributor/lifecycle 面向目录包）；详情 SKILL.md 预览读文件本体；files 区块显示单文件。L10n 加降级文案一条
- 同名双形态同目录（目录包+扁平 `.md` 同名并存）：极罕见；落点面板 `shaByPath` 构建 uniquing 优先目录包条目，去重为一行，文档标注不判优先级（无官方细则，中性）

### C. 遮蔽升级（一行 + 测试）

- `SkillShadowPolicy.precedence(for: "deepseek") → .projectOverUser`（官方 rank 100 > 400）
- 生效关系区块/文案零改动（「项目级 > 用户级」为通用文案）

### D. 测试（TDD）

| 层 | 用例 |
|---|---|
| DomainKit | layout legacy 解码默认 directoryPackage；roundtrip |
| InfraKit/SkillParsing | 扁平：frontmatter name 优先 / 缺省文件名 / 非 md 忽略 / 空文件 issue / 编码异常 |
| InfraKit/SkillCollector | root 直属 .md 收集；子目录内 .md 不收；隐藏文件跳过；目录包与扁平并存互不干扰 |
| InfraKit/CatalogBuilder | 扁平条目 layout=.flatFile + scope 链路正确 |
| InfraKit/ShadowRelation | deepseek project+user → 标注；deepseek 仅 user → 中性 |
| AgentSpec 清单 | all 计数 10→11（如有硬编码断言处更新） |
| AppCore/L10n | 扁平降级文案双语 |

### E. 真机 + 发版 v0.5.0

- 本机无 dsh：造 fixture `~/.dsh/skills/`（目录包 + 扁平各一 + 同名项目级副本触发遮蔽）验证扫描/详情/生效区块/降级按钮；测完清理
- 发版：0.4.1→0.5.0（build 6）→ release notes 中英（DeepSeek Harness 收录 + 扁平 skill + 遮蔽升级 + known limitations）→ universal 分建+lipo → zip → 冒烟 → gh release → /Applications

## 已知盲区（v1 明示不做）

- `~/.agents/skills`（rank 500）与项目级 `.agents/skills`（rank 200）接入 deepseek 的串扰展示（v2）
- dsh `customSkillDirs` / `bundledSkillDir`（Config 注入，AK 无法感知）
- kebab-case 校验、bundle 资源文件展示
- 「沿 .git 向上找最近祖先」通用项目根发现（AK 无 cwd 概念）
- 扁平 skill 在线操作（停用/分发/回收站）——v2 开放
