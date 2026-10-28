# skill-tags Specification

## Purpose

让用户以自定义标签组织本机 skill：为任意 skill 打上个人工作流相关的标签（如「写作」「实验」），标签支撑导航分组与筛选，跨重启持久化且不依赖文件系统内容。

## Requirements


### Requirement: 标签管理
用户 SHALL 能为任一本机 skill 增加或移除自定义标签；标签名 MUST 非空且去重；用户 SHALL 能重命名标签（自动应用到全部关联 skill）与删除标签（仅删除标签本身，不影响 skill 文件）。

#### Scenario: 打标签
- **WHEN** 用户在某 skill 的详情中添加新标签并在列表中查看
- **THEN** 该 skill 携带新标签；同名标签在系统中只存在一份定义

#### Scenario: 重命名与删除标签
- **WHEN** 用户重命名某标签后查看原关联 skill
- **THEN** 全部关联 skill 的标签同步更新；删除标签后关联 skill 文件不受任何影响

### Requirement: 标签持久化与重扫稳定
标签 SHALL 持久存储于 AgentKeeper 应用数据目录；重扫描、禁用/启用、快照恢复 MUST NOT 丢失既有关联；skill 被禁用或搬移后关联 MUST 保留，重新启用后自动恢复可见。

#### Scenario: 重扫不丢标签
- **WHEN** 用户修改 skill 内容触发自动重扫描
- **THEN** 该 skill 的自定义标签在刷新后保持不变

#### Scenario: 禁用期间标签保留
- **WHEN** 用户禁用一个带标签的 skill 后再启用
- **THEN** 启用后该 skill 仍带有原标签

### Requirement: 标签导航与筛选
用户 SHALL 能在导航树按标签分组浏览 skill，并能在统一视图中按标签筛选；标签作用域 MUST 支持「已禁用」的 skill（即禁用条目同样可携带标签出现在分组中）。

#### Scenario: 按标签筛选
- **WHEN** 用户在筛选器中选择某标签
- **THEN** 列表仅显示携带该标签的 skill（含已禁用条目并带禁用标记）

#### Scenario: 标签分组浏览
- **WHEN** 用户展开导航树的「标签」分组
- **THEN** 看到按标签名分组的子分组（含条目数量），选择某标签仅显示关联 skill

### Requirement: 未匹配 skill 的标签悬挂提示
当某 skill 的目录已从本机消失而其标签关联仍被存储时，系统 SHALL 在筛选该标签时提示存在「已消失」的关联条目数量，MUST NOT 在主列表中显示不存在的 skill。

#### Scenario: 悬挂关联被提示
- **WHEN** 用户删除某 skill 目录后按其标签筛选
- **THEN** 主列表不显示该 skill，筛选器提示若干条关联已失效的计数，用户可一键清理失效关联
