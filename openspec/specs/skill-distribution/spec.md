# skill-distribution Specification

## Purpose

为 skill 提供从来源到目标的分发能力：把已存在的 skill 或外部来源（本地目录、git 仓库）内容安装到用户指定的 agent skill 目录；同名分发到多个 agent 自动形成 multi-agent 铺设。分发过程遵循文件的原子性与冲突保护原则。

## Requirements


### Requirement: 跨 agent 安装
用户 SHALL 能把本机任一已识别的 skill 安装到其他 agent 的 skill 目录；安装 SHALL 以复制方式非破坏地进行（来源目录 MUST NOT 被修改或删除）；安装完成后目标出现在目录中并触发重扫描。

#### Scenario: 安装到空目标
- **WHEN** 用户把某 agent 的 skill A 安装到另一个 agent 的 skill 目录
- **THEN** 目标 agent 目录出现内容一致的 skill 副本，来源 skill 保持原样，列表在重扫后同时展示两者

#### Scenario: 目标冲突被保护
- **WHEN** 目标目录已存在同名 skill 且内容指纹不一致
- **THEN** 操作中止，UI 展示冲突明细（目标路径、双方指纹），目标与来源均无改动

#### Scenario: 同名同内容视为已铺设
- **WHEN** 目标目录已存在同名且指纹一致的 skill
- **THEN** 不重复复制，系统报告该铺设关系已存在

### Requirement: multi-agent 铺设的生成语义
系统 SHALL 在安装产生的同名且指纹一致的条目间建立铺设关联：两条记录均标记 `multi-agent 铺设` 并在详情中互相链接；用户 SHALL 能从铺设记录一键查看其全部落点。

#### Scenario: 铺设记录互相链接
- **WHEN** 用户查看一条 multi-agent 铺设的 skill
- **THEN** 详情列出该 skill 在本机的全部落点（agent 与路径），点击任一落点可跳转查看

#### Scenario: 铺设一致性提示
- **WHEN** 同名铺设的落点间出现指纹分歧（某个落点被外部修改）
- **THEN** 列表对该落点显示「已分歧」提示，并给出「用此版本更新所有落点」的入口

### Requirement: 本地目录导入
用户 SHALL 能选择本机任一目录作为 skill 导入到指定 agent；系统 MUST 校验该目录符合 skill 识别规则（含 SKILL.md 与合法 frontmatter），校验通过后以复制方式安装；来源目录保持不变。

#### Scenario: 合法目录导入成功
- **WHEN** 用户选择一个含合法 SKILL.md 的目录并导入某 agent
- **THEN** 该目录内容被复制到目标 agent 的 skill 目录并出现在列表中

#### Scenario: 非法目录被拒绝
- **WHEN** 用户选择的目录不含 SKILL.md 或 frontmatter 不合法
- **THEN** 导入被拒绝，界面说明具体缺失项，MUST NOT 产生半成品副本

#### Scenario: 导入目标冲突保护
- **WHEN** 目标 agent skill 目录已存在同名 skill
- **THEN** 与跨 agent 安装相同的冲突保护规则适用：中止、展示指纹冲突，不覆盖

### Requirement: git 来源安装
用户 SHALL 能通过 git URL（支持 HTTPS/SSH 形式与本机路径形式）安装 skill：系统 SHALL 将仓库 clone 到临时目录，按 skill 识别规则定位内容（仓库根目录本身或其一级子目录可以是 skill），校验通过后安装到指定 agent；网络或身份验证失败时 MUST 清理临时区并如实报告失败原因。

#### Scenario: 从 git 仓库安装单 skill 仓库
- **WHEN** 用户输入一个仓库根目录即为 skill 的 git URL 并安装
- **THEN** 内容被安装到目标 agent 的 skill 目录，临时 clone 目录被清理

#### Scenario: 从多 skill 仓库安装
- **WHEN** 仓库一级子目录中发现多个合法 skill
- **THEN** UI 列出全部候选供用户勾选，勾选的逐个安装并按冲突规则处理

#### Scenario: clone 失败不残留
- **WHEN** git URL 无法访问或验证失败
- **THEN** 操作中止并报告失败原因（如网络、认证、仓库不存在），临时区被清理，目标 agent 目录无任何改动

### Requirement: 分发操作可审计与防误删
分发类操作 SHALL 记录操作历史（时间、来源、目标、结果）；分发 MUST NOT 删除来源或目标的任何既有文件，任何清理动作遵守删除确认要求。

#### Scenario: 查看分发历史
- **WHEN** 用户打开操作历史面板
- **THEN** 看到安装/导入/clone 安装记录（含来源与目标），成功与失败状态明确

#### Scenario: 分发永不删除来源
- **WHEN** 安装完成后用户检查来源目录
- **THEN** 来源目录内容与安装前一致
