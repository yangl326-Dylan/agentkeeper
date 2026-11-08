# Skill 健康检查 v1 设计

日期：2026-11-08
状态：已确认

## 背景

GitHub 调研（2026-11）显示 skill 质量类痛点有真实用户反馈背书：

- `claude-api` skill 撑爆上下文（anthropics/skills#1486）——体积膨胀
- evals 中 skill 触发率 0%（#556）——frontmatter 质量（description）是触发可靠性的代理指标
- "装了一堆复杂 skill 后 claude 全乱了"（#63）——skill 蔓延失控
- `disable-model-invocation` 各 agent 支持不一（opencode#34498）——字段兼容性（v1.5）

## 原则

**只做客观问题检查，零阈值判定。** 体积只展示数值不做警告；健康徽章只标客观缺陷（缺字段、空文件、坏链接）。没有主观参数，就没有「为什么警告我」的争议。

## 检查项（v1）

| kind | 判定 | 调研背书 |
|---|---|---|
| `missingFrontmatter` | SKILL.md 无 `---` frontmatter 块（正文非空） | #556 |
| `missingName` | 有 frontmatter 块但无 `name` | #556 |
| `missingDescription` | 有 frontmatter 块但无 `description`（空串视为缺失） | #556 |
| `emptySkillMd` | SKILL.md 0 字节或 trim 后为空 | #63 |
| `invalidEncoding` | SKILL.md 非 UTF-8（`String(contentsOf:encoding:.utf8)` 抛错） | #1061 Windows 编码类 |
| `brokenSymlink` | 目录内符号链接目标不存在 | 结构完整性 |

体积事实（只展示）：`totalBytes`（非隐藏常规文件总和，即 agent 实际加载口径）、`skillMdBytes`、已有 `fileCount`。

## 数据模型（DomainKit）

```swift
public enum SkillIssueKind: Hashable, Codable, Sendable {
    case missingFrontmatter, missingName, missingDescription
    case emptySkillMd, invalidEncoding, brokenSymlink
}

public struct SkillIssue: Hashable, Codable, Sendable {
    public var kind: SkillIssueKind
    public init(kind: SkillIssueKind)
}

// Skill 新增（带默认值；自定义 Codable decodeIfPresent，旧编码输入可解码）
public var totalBytes: Int = 0
public var skillMdBytes: Int = 0
public var issues: [SkillIssue] = []
```

Skill 目录为内存重建（不落盘），Codable 兼容仅防御测试/未来的缓存场景。

## 扫描管线（InfraKit）

- `FrontmatterParser` 新增 `parseDetailed(markdown:) -> (hasFrontmatter: Bool, name: String?, description: String?)`；现有 `parse` 委托之（SkillDistributor 调用方不动）。空串 description 归一为 nil。
- `DirectoryFingerprint` 新增 `totalBytes: Int`——指纹枚举已逐文件取 size，求和顺路完成，零额外 IO；进程级缓存透明携带。
- `SkillParsing.parseDirectory`：
  - UTF-8 解码改 do/catch → 失败记 `invalidEncoding`（markdown 按空处理，不再双重报 `emptySkillMd`）
  - `emptySkillMd` / `missingFrontmatter` / `missingName` / `missingDescription` 由解码结果 + parseDetailed 判定
  - 符号链接轻量枚举（现有枚举跳过 symlink，补一次仅查 symlink 的遍历，目标不存在 → `brokenSymlink`）
  - `skillMdBytes` 取文件属性
- `ParsedSkill` 新增 `totalBytes` / `skillMdBytes` / `issues` 字段（带默认值）。
- `CatalogBuilder` 透传进 `Skill`。

## UI（AgentKeeperUI）

- **列表行**（`SkillRowView`）：`issues` 非空时 scope 徽章左侧加黄色 `exclamationmark.triangle.fill` 小徽章，`.help` 显示问题数；无问题零噪音。
- **详情面板**（`SkillDetailContent`）：`scopeBadge` 之后插入 `healthSection`——
  - 有问题：区块标题 + 逐条本地化问题文案
  - 无问题：只显示一行体积事实（`总大小 · N files · SKILL.md x`），ByteCountFormatter 人类可读
- **L10n**：区块标题 + 6 条问题文案中英双语（沿用现有 L10n 模式与测试断言）。

## 测试（TDD）

| 层 | 用例 |
|---|---|
| DomainKit | `SkillIssue` 编解码 roundtrip；Skill 旧 JSON（缺新字段）解码得到默认值 |
| InfraKit | fixture 临时目录逐项触发 6 种 issue；正常 skill 无 issue；totalBytes 汇总正确（多文件）；parseDetailed 四分支；空 description 归一 nil |
| AppCore | L10n 双语非空且不同 |
| UI 探针 | 行徽章渲染出像素；详情健康区块渲染出像素（含体积事实行） |

## 非目标

- 体积阈值警告与设置页可调阈值
- 跨 agent frontmatter 字段兼容矩阵（v1.5）
- `ak health` CLI（v1.5）
- 侧栏「健康问题」聚合视图、「只看有问题」筛选
- 触发率评估（需跑模型）
