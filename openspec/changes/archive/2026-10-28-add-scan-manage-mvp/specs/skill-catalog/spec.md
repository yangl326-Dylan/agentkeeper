# Spec Delta

## Purpose

发现、解析并索引本机所有 agent 的 skill，为每个 skill 建立统一条目（元数据、作用域、内容指纹），支撑列表查看、筛选与详情展示。文件系统为本能力的唯一真相源，索引仅为缓存。

## ADDED Requirements

### Requirement: Skill 自动发现
系统 SHALL 自动发现每个 agent skill 根目录下的 skill，MVP 的识别规则 MUST 以「目录内包含 SKILL.md 及合法 frontmatter」为准，并解析出 name 与 description。

#### Scenario: 标准 skill 被识别
- **WHEN** 某 skill 目录包含带 frontmatter 的 `SKILL.md`
- **THEN** 该目录成为一条 skill 记录，展示其 name、description、所在 agent 与路径

#### Scenario: 嵌套目录遍历
- **WHEN** skill 根目录下存在多级子目录
- **THEN** 系统递归发现所有符合识别规则的 skill，不因目录深度遗漏

#### Scenario: 非 skill 目录被忽略
- **WHEN** 某目录不含 SKILL.md
- **THEN** 该目录不产生 skill 记录，也不产生错误

### Requirement: 作用域标记
系统 SHALL 为每个 skill 标记作用域：位于单一 agent 私有目录 → `agent 专属`；位于被两个及以上 agent 共同引用的目录 → `共享（全局）`；位于某项目根内的目录 → `项目级`；同名内容一致且铺设在多个 agent 目录 → `multi-agent 铺设`。作用域判定必须是确定性的、可解释的（用户能看到判定原因）。

#### Scenario: 全局 skill 标记
- **WHEN** 某 skill 位于 `~/.claude/skills/` 且该目录被多个 agent 注册为读取路径
- **THEN** 该 skill 显示 `共享（全局）` 标记，详情中列出共享它的 agent 清单

#### Scenario: agent 专属标记
- **WHEN** 某 skill 位于仅被单一 agent 引用的目录
- **THEN** 该 skill 显示为该 agent 专属，并注明所属目录

#### Scenario: multi-agent 铺设识别
- **WHEN** 两个 agent 各自目录下存在同名且内容指纹一致的 skill
- **THEN** 两条记录均标记为 `multi-agent 铺设` 并互相链接

#### Scenario: 项目级标记与项目标签
- **WHEN** 某 skill 位于一个已发现项目根内的 skill 目录
- **THEN** 该 skill 标记为 `项目级`，并自动携带项目标签（项目名）与项目根路径

### Requirement: 统一导航分组
系统 SHALL 在导航树按「全局 / agent 专属 / 项目」三类组织 skill；项目类下 SHALL 按项目名自动分组；每个分组 MUST 显示条目数量。

#### Scenario: 项目分组浏览
- **WHEN** 用户展开导航树的「项目」分组
- **THEN** 看到按项目名分组的子分组（含各自 skill 数量），选择某项目仅展示该项目的 skill

### Requirement: 内容指纹
系统 SHALL 为每个 skill 计算 SHA256 内容指纹，用于变更检测与快照去重；指纹 SHOULD 覆盖 SKILL.md 与随附脚本文件。

#### Scenario: 变更后指纹更新
- **WHEN** skill 目录内任一文件内容被外部修改
- **THEN** 该 skill 的指纹与最后修改时间被更新，UI 在刷新后展示新指纹状态

### Requirement: 外部变更自动感知
系统 SHALL 通过文件系统事件监听所有已注册 skill 目录；外部（终端/编辑器）做出的修改 MUST 在数秒内反映到列表与详情视图，且 MUST NOT 要求用户手动重启或手动刷新。

#### Scenario: 终端修改文件后自动刷新
- **WHEN** 用户在终端修改了某 skill 的 SKILL.md
- **THEN** 该 skill 在数秒内被自动增量重扫描，并在 UI 中标记内容已变更、指纹/时间字段及时更新

### Requirement: 统一查询视图
用户 SHALL 能在统一视图中按 agent、作用域、名称进行筛选与搜索；查询 MUST 基于索引缓存并在索引与文件系统真相不一致时以文件系统为准（自动纠偏）。

#### Scenario: 按作用域筛选
- **WHEN** 用户选择筛选「共享（全局）」
- **THEN** 列表仅显示作用域为共享（全局）的 skill

#### Scenario: 索引失真自动纠偏
- **WHEN** 索引中的一条 skill 在磁盘上已被外部删除
- **THEN** 系统在感知到事件后移除该条索引记录，列表不再显示该 skill，且不显示错误弹窗
