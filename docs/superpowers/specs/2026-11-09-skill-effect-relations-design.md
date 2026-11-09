# 生效关系可视化 v1 设计

日期：2026-11-09 · 状态：已确认（用户免确认授权推进）
决策依据：`docs/research/2026-11-09-skill-management-pain-points.md` 痛点 #1（同名遮蔽）+#10（目录串扰）

## 目标

回答用户能力矩阵研究里最值钱的一个问题：**「目录里这么多 skill，实际生效的是哪一个？」** v1 覆盖两件事：

1. **同名遮蔽**：同 agent 内同名 skill 存在项目级与用户级副本时，标注生效/被遮蔽关系
2. **串扰说明**：目录被多 agent 加载、或用户级目录可能被外部工具读取的事实说明

不做（YAGNI）：依赖断裂预警（需解析 skill 内容互链）、侧栏聚合筛选、列表行徽章。

## 判定规则（官方优先级硬编码）

| Agent | 规则 | 依据 |
|---|---|---|
| claude-code | 项目级 `.claude/skills` > 用户级 `~/.claude/skills`；同名时项目级生效 | 官方 skills 文档 |
| 其他 agent | v1 不判遮蔽，只报同名副本事实 | 无官方文档，宁可少说 |

判定条件（全部满足才标注）：
- 同一 agent（`scope.agentIDForOwner` 相同）+ 同一 effective name（frontmatter name，缺省目录名）
- 一个 `.project` scope 副本 + 一个 `.agentOnly`（即 user 级）副本，且该 agent 有 projectOverUser 规则
- 不同优先级出现多个副本（如两个项目）时保持中性，不猜全局排序

## 数据模型（DomainKit）

```swift
// Skill 新增（CodingKeys + decodeIfPresent 兼容，与健康检查字段同模式）
public var shadowedBy: String?    // 遮蔽我的生效副本 skill id；nil = 生效或无关系
public var shadowedCount: Int = 0 // 我遮蔽的同名低优先级副本数（仅生效副本 >0）
```

## 扫描管线（InfraKit）

- 新增 `SkillShadowPolicy`：`static func precedence(for agentID:) -> Precedence`（`.projectOverUser` / `.none`），内置表只有 claude-code，随官方文档补齐其他 agent。
- `CatalogBuilder` 在 `relabelMultiAgent` 之后追加 `labelShadowing(in:)`：
  - 按 `(agentIDForOwner, name)` 分组（只看 agentOnly/project scope）
  - 组内同时存在 agentOnly + project 且 policy == .projectOverUser → agentOnly 记 `shadowedBy = project.id`，project 记 `shadowedCount`
  - 不改变排序 distintos；`issues`/健康字段不动

## UI（AgentKeeperUI）

详情面板 `scopeBadge` 与 `SkillHealthSection` 之间插入 `SkillEffectSection`（新文件）：

- **被遮蔽**（shadowedBy != nil）：黄色 `eye.slash` 图标 + 文案「同名项目级 skill 生效，agent 不会加载当前副本（项目级 > 用户级）」
- **遮蔽别人**（shadowedCount > 0）：`eye` 图标 +「当前副本生效；另有 N 个更低优先级同名副本被遮蔽」
- **串扰**：`scope == .multiAgent(ids)` → 「该内容由多个 agent 共同加载：id1、id2」；`scope == .agentOnly` → 次要行「用户级目录也可能被其他工具读取（如 Cursor 曾激进加载 ~/.claude/skills）」
- 无任何关系信息时不渲染区块（零噪音）

L10n：区块标题 + 4 类文案中英双语（沿用 L10n 测试模式）。

## 测试（TDD）

| 层 | 用例 |
|---|---|
| DomainKit | 新字段 legacy JSON 解码默认值；roundtrip |
| InfraKit | claude-code 同名 project+user → 遮蔽标注正确（方向、id、count）；同 project 两个项目同名 → 中性；无 policy agent 同名 → 中性；不同名不同 agent 不标注；multiAgent/global 不参与 |
| AppCore | L10n 双语 |
| UI 探针 | 生效区块三种状态渲染出像素 |

## 非目标

- 列表行内徽章 / 侧栏聚合（依用户选择「仅详情区块」）
- 其他 agent 的实验性优先级反推
- 依赖断裂预警 v2

## 实战补记（实现期决定）

- **crossNote 门控**：用户级串扰提示仅随区块渲染（区块本体无行时不出现）——保证「生效关系」零噪音语义完整。
- 验证手段：离屏探针三态渲染（probe-effect.png）+ 真机键盘导航（合成鼠标点击无法选中 SwiftUI List；可靠通路 = 方向键/Tab/Return）。
