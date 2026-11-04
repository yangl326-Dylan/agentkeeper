# agent-discovery Specification

## Purpose

检测本机已安装的 AI coding agent，统一报告其安装状态与 skill 根目录清单，为 skill 扫描提供权威的 agent 注册数据。该能力以可插拔的 adapter 体系承载，保证新 agent 的接入不影响既有行为。

## Requirements

### Requirement: Agent detection
系统 SHALL 通过适配器机制自动检测本机已安装的 agent，MVP MUST 内置以下 6 组适配器：Claude Code、OpenAI Codex CLI、Gemini CLI、OpenCode、OpenClaw、pi/oh-my-pi（同源 harness，一个适配器覆盖两者）；检测结果 MUST 包含 agent 名称、安装状态、配置目录与 skill 根目录列表（含用户级与项目级）。

#### Scenario: 已安装的 agent 被识别
- **WHEN** 本机存在某 agent 的配置目录（如 `~/.claude/`）且配置可读
- **THEN** 扫描结果中出现该 agent，标记为已安装，并附带其用户级 skill 目录与已知项目根列表

#### Scenario: 未安装的 agent 被标记为未安装
- **WHEN** 本机不存在某 agent 的配置目录
- **THEN** 该 agent 在结果中标记为未安装，且系统不得因检测不完整而报错

#### Scenario: 目录结构不可识别时降级
- **WHEN** 某 agent 的配置目录存在但内部结构无法匹配任何已知版本规则
- **THEN** 系统 SHALL 将该 agent 标记为「无法识别（结构未知）」，保留目录路径信息，MUST NOT 抛出错误或中断整体扫描

#### Scenario: 同源 harness 双识别（pi/oh-my-pi）
- **WHEN** 本机安装了 pi 或其 fork oh-my-pi
- **THEN** 适配器分别识别出两者各自的配置与 skill 目录标识归属，不发生串扰或重复计数

### Requirement: 项目根发现与项目级扫描
系统 SHALL 从 agent 自身维护的配置/会话记录中发现已知项目根，并对每个项目根下的 skill 目录执行扫描；对不暴露项目根记录的 agent，项目级扫描 MUST 仅使用用户在设置中明确添加的目录。系统 MUST NOT 在未经用户知情的情况下递归扫描磁盘上的任意目录。

#### Scenario: 从 agent 配置发现项目根
- **WHEN** 某 agent 的配置文件中记录了用户曾打开过的项目目录
- **THEN** 系统将其列为该项目 agent 的项目根，并扫描其中的项目级 skill 目录

#### Scenario: 无项目根记录的 agent
- **WHEN** 某适配器没有可读取的项目根记录来源
- **THEN** 该 agent 的项目级扫描仅在用户手动添加目录后发生，UI 说明这一限制

### Requirement: 扫描范围可见
用户 SHALL 能查看当前扫描范围清单（哪些用户级目录、哪些项目根）并自行增删项目根；扫描范围变更 MUST 触发重新扫描。

#### Scenario: 查看与增删项目根
- **WHEN** 用户打开扫描范围设置
- **THEN** 看到按 agent 分组的扫描范围清单，可新增或移除项目根，保存后触发重扫

### Requirement: Adapter 可插拔
系统 SHALL 以注册表方式管理适配器，新增一个 agent 适配器 MUST NOT 需要修改扫描调度器与其他适配器的代码。

#### Scenario: 注册表遍历
- **WHEN** 发起一次全量扫描
- **THEN** 调度器 SHALL 遍历注册表中所有已注册适配器，并逐个产出标准的扫描报告

### Requirement: 用户自定义 agent
系统 SHALL 支持从 `~/.agentkeeper/agents.json` 加载用户自定义 agent，使其与内置 agent 走同一条扫描与展示管线；加载 MUST NOT 因单个条目非法而中断扫描。

#### Scenario: 自定义 agent 被扫描
- **WHEN** `agents.json` 声明了一个 id 不与内置冲突、路径均相对家目录的 agent，且其检测目录存在
- **THEN** 该 agent 出现在扫描结果、侧栏、菜单栏与 `ak doctor` 中，其 skill 根与项目级目录被正常扫描

#### Scenario: 内置 id 不可被覆盖
- **WHEN** 自定义条目的 id 与某个内置 agent 相同
- **THEN** 该条目被忽略，内置 agent 行为不变，并产出一条可见诊断说明原因

#### Scenario: 非法条目降级
- **WHEN** 自定义条目包含非法 id、绝对路径、`..`、空 `detectionSubpaths` 或损坏的 JSON
- **THEN** 仅该条目被忽略，扫描继续，诊断中包含 `agents.json` 路径与具体原因

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
