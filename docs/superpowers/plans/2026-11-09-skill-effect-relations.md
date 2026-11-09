# 生效关系可视化 v1 实施计划

> 用 superpowers:executing-plans 逐 Task 执行；用户已授权免确认推进，验证通过后发 v0.4.1。

验证基线（每 Task 复用）：

```bash
pkill -9 -f swiftpm-testing-helper 2>/dev/null
swift build 2>&1 | grep -cE "error|warning"   # 期望 0
swift test --filter <Suite> 2>&1 | tail -4
```

### Task 1: DomainKit——Skill 新增 shadowedBy / shadowedCount

- Modify: `Sources/DomainKit/CoreModels.swift`（Skill 属性 + init + CodingKeys + init(from:)）
- Test: `Tests/DomainKitTests/ModelTests.swift`（SkillHealthModelTests 内追加两断言：legacy JSON 解码得 nil/0；roundtrip 保留字段值）

层面的具体改动（accumulated pattern 与 totalBytes 一致）：
- 属性：`public var shadowedBy: String?;  public var shadowedCount: Int = 0`（init 参数带默认值）
- CodingKeys 追加 case；init(from:) `decodeIfPresent ??`。

- [ ] 1.1 失败测试（Roundtrip 含非 nil 值 + legacy 缺字段）
- [ ] 1.2 实现 → 通过 → `swift test --filter SkillHealthModelTests` 全绿
- [ ] 1.3 commit：`feat(effect): Skill 增加 shadow 关系字段`

### Task 2: SkillShadowPolicy + CatalogBuilder.labelShadowing

- Modify: `Sources/InfraKit/SkillParsing.swift`（放 SkillShadowPolicy——同文件事实类工具族）或 `Sources/InfraKit/CatalogBuilder.swift`
- Test: `Tests/InfraKitTests/ShadowRelationTests.swift`（新建，复用 CatalogBuilderTests 的 makeFakeHome/agent 模式 + SkillRoot(level:) 构造）

用例：
1. 同 agent（claude-code）同名，project root 副本 + user 副本 → user 副本 shadowedBy=project 副本 id；project shadowedCount==1
2. 仅 user 副本 → 无标注
3. 同名但都在 project scope 两个项目 → 中性（不标注）
4. 同名副本但 agent 无 policy（opencode）→ 中性
5. 不同名（name 不同）→ 不标注
6. global/multiAgent scope 不参与分组
7. policy 与 group 相互独立：agentOnly 遮蔽反向（user 遮蔽 project）不成立

实现要点：
- `SkillShadowPolicy.precedence(for:)`：内置 `["claude-code": .projectOverUser]`，其余 `.none`
- `labelShadowing` 在 `relabelMultiAgent` 结果上执行，再走原有 sort
- `skillID` 生成依赖 scope 的路径段——测试断言用 id 相等提取（先取 project 副本 id 再比对 user.shadowedBy）

- [ ] 2.1 失败测试 → 2.2 实现 → 通过 → `swift test --filter "ShadowRelation|CatalogBuilder"` 无回归
- [ ] 2.3 commit：`feat(effect): catalog 标注同名遮蔽关系（claude-code 项目级>用户级）`

### Task 3: L10n

- Modify: `Sources/AppCore/L10n.swift`
- 变域键：
  - `effectSectionTitle`（生效关系 / Effect）
  - `effectShadowedNotice`（被遮蔽文案，含规则说明）
  - `effectShadowsCount(_ count: Int)`（遮蔽 N 个）
  - `effectMultiAgent(_ agents: String)`（多 agent 共同加载）
  - `effectCrossNote`（用户级目录串扰提示）
  - `effectNoneNotice`（中性提示：同名副本共存但无法判定优先级时不渲染——无需键，删除）
- Test: `Tests/AppCoreTests/L10nTests.swift` `effectStringsAreLocalized`（双语非空且不同；count 函数含数字）

- [ ] 3.1 失败 → 实现 → 通过 → commit：`feat(effect): 生效关系中英文案`

### Task 4: UI——SkillEffectSection + 详情嵌入

- Create: `Sources/AgentKeeperUI/SkillEffectSection.swift`
- Modify: `Sources/AgentKeeperUI/RootView.swift`（SkillDetailContent body: scopeBadge 之后插 `SkillEffectSection(skill: env.skillCapture)`；注意 SkillEffectSection 只接 skill + l10n）
- Test: `Tests/AgentKeeperTests/ProbeButton.swift` ProbeRender 追加 `effectSectionRendersToPixels`（三态：被遮蔽/生效+遮蔽他人/多 agent 串扰，渲染 png 到 /tmp/ak-ui/probe-effect.png）

- [ ] 4.1 失败探针 → 4.2 实现（区块零噪音：无信息不渲染 Heading）→ 4.3 探针通过 + 目检 → commit：`feat(effect): 详情生效关系区块`

### Task 5: 全量验证 + 文档 + 真机 + 发 v0.4.1

- [ ] 5.1 `swift build` 0 warning + `swift test --no-parallel` 全绿
- [ ] 5.2 README：功能清单 + Roadmap 勾「生效关系 v1」；调研文档状态同步
- [ ] 5.3 `scripts/build-app.sh release` 装机真机验证：详情面板出现生效区块（无关系 skill 不显示 / multiAgent skill 显示串扰文案）；遮蔽态用 probe png 目检兜底（若无 project root 记录）
- [ ] 5.4 发版流程（版本号 0.4.0→0.4.1，build 5）：版本号 → release notes 中英（含 sha256 换行 + 生效关系 v1）→ 双构建 lipo 合成 → ditto zip（app + cli）→ tag v0.4.1 → `gh release create` → `releases/latest` 验证 → 本地 /Applications 安装
- [ ] 5.5 push（commit + tag）
