# skill-lifecycle Specification

## Purpose

为 skill 提供安全的启用/禁用与文件操作行为：通过原子搬移实现状态切换，通过 manifest 记录原始位置，通过冲突检测与自动回滚保证任何失败都不破坏用户数据。

## Requirements

### Requirement: 禁用机制
系统 SHALL 将被禁用的 skill 目录原子搬移到 `~/.agentkeeper/disabled/<agent-identifier>/<skill-name>/`，并 MUST 在该目录中记录一份 manifest，包含原始完整路径、禁用时间与内容指纹。

#### Scenario: 成功禁用
- **WHEN** 用户对一个已启用的 skill 执行禁用
- **THEN** skill 目录从 agent 目录消失、agent 不再加载它，skill 在列表中显示为已禁用，manifest 记录了原始路径

#### Scenario: 禁用后 agent 行为不变
- **WHEN** skill 被禁用后用户在该 agent 的会话中运行
- **THEN** agent 无法看到该 skill（搬移目标不属于任何 agent 的读取路径）

### Requirement: 启用机制
系统 SHALL 依据 manifest 将已禁用的 skill 搬回原始路径；若原路径已被占用，系统 MUST 中止并在 UI 提示冲突，MUST NOT 覆盖或删除原路径上的任何内容。

#### Scenario: 成功恢复启用
- **WHEN** 用户对已禁用 skill 执行启用且原路径未被占用
- **THEN** skill 目录回到原始位置，agent 重新可见该 skill，manifest 被清理

#### Scenario: 原路径冲突被保护
- **WHEN** 执行启用时原路径上已存在同名目录
- **THEN** 操作中止，UI 展示冲突明细（路径、占用方），双方文件均无任何改动

### Requirement: 文件操作原子性与回滚
所有启用/禁用涉及的多步文件操作 SHALL 遵循「先复制后改名（同物理卷）」的原子化策略；任一步骤失败时系统 MUST 自动回滚到操作前状态，并向用户如实报告失败原因，MUST NOT 留下半搬移的中间态目录。

#### Scenario: 失败自动回滚
- **WHEN** 禁用过程中发生磁盘错误或权限错误导致搬移中断
- **THEN** 已发生的搬移动作被回滚，agent 目录与禁用区恢复操作前状态，用户收到失败说明

### Requirement: 删除确认
系统 SHALL 对任何最终删除类操作（如在冲突清理中选择删除）执行显式确认；未经用户确认 MUST NOT 永久删除任何 skill 文件。

#### Scenario: 破坏性操作需确认
- **WHEN** 用户触发一个会永久删除 skill 文件的清理动作
- **THEN** 系统弹出确认框，列明将被删除的路径清单，确认后才执行

### Requirement: 操作历史可审计
系统 SHALL 记录每次启用/禁用操作的日志（时间、skill、方向、结果），用户 SHALL 能在 UI 中查看最近操作记录。

#### Scenario: 查看操作历史
- **WHEN** 用户打开操作历史面板
- **THEN** 看到按时间倒序的启用/禁用记录，包含成功或失败状态
