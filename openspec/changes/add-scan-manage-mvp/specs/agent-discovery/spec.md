# Spec Delta

## Purpose

检测本机已安装的 AI coding agent，统一报告其安装状态与 skill 根目录清单，为 skill 扫描提供权威的 agent 注册数据。该能力以可插拔的 adapter 体系承载，保证新 agent 的接入不影响既有行为。

## ADDED Requirements

### Requirement: Agent detection
系统 SHALL 通过适配器机制自动检测本机已安装的 agent，MVP MUST 至少内置 Claude Code 与 OpenCode 两种适配器，且检测结果 MUST 包含 agent 名称、安装状态、配置目录与 skill 根目录列表。

#### Scenario: 已安装的 agent 被识别
- **WHEN** 本机存在 `~/.claude/` 目录且配置可读
- **THEN** 扫描结果中出现名为 Claude Code 的 agent，标记为已安装，并附带其用户级 skill 目录 `~/.claude/skills/`

#### Scenario: 未安装的 agent 被标记为未安装
- **WHEN** 本机不存在某 agent 的配置目录
- **THEN** 该 agent 在结果中标记为未安装，且系统不得因检测不完整而报错

#### Scenario: 目录结构不可识别时降级
- **WHEN** 某 agent 的配置目录存在但内部结构无法匹配任何已知版本规则
- **THEN** 系统 SHALL 将该 agent 标记为「无法识别（结构未知）」，保留目录路径信息，MUST NOT 抛出错误或中断整体扫描

### Requirement: Adapter 可插拔
系统 SHALL 以注册表方式管理适配器，新增一个 agent 适配器 MUST NOT 需要修改扫描调度器与其他适配器的代码。

#### Scenario: 注册表遍历
- **WHEN** 发起一次全量扫描
- **THEN** 调度器 SHALL 遍历注册表中所有已注册适配器，并逐个产出标准的扫描报告

### Requirement: 扫描进度可感知
用户 SHALL 能在界面上看到扫描过程的实时状态（开始/进行中/完成/失败），扫描 MUST 在后台线程执行且 MUST NOT 阻塞 UI。

#### Scenario: 扫描进行中的状态展示
- **WHEN** 用户发起全盘扫描
- **THEN** UI 出现扫描进行中的指示，完成后转为就绪状态并展示结果数量

### Requirement: 权限不足的显式反馈
当系统无法读取某个 agent 的目录（权限被拒绝）时，系统 SHALL 显式列出该目录与失败原因，并 MUST NOT 将其静默当作「无 skill」处理。

#### Scenario: 目录权限被拒绝
- **WHEN** 扫描某 skill 目录时 macOS 返回权限错误
- **THEN** 界面在对应 agent/目录条目上显示权限受限标记，并给出重新授权的引导入口
