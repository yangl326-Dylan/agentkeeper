# Spec Delta

## Purpose

让 AgentKeeper 的 core 与 `ak` CLI 在 macOS 与 Linux（Ubuntu 24.04+）上行为一致地可用：CLI 功能对等、构建与测试双平台受 CI 强制、发布产物覆盖两个平台，为 Linux GUI（`add-linux-app`）提供平台无关地基。

## ADDED Requirements

### Requirement: ak CLI 在 Linux 可用
`ak` SHALL 可在 Ubuntu 24.04+ 上以单二进制形态运行（无需 Swift 工具链），且 `ak list`、`ak doctor` 等命令的输出结构与语义 SHALL 与 macOS 版本一致。

#### Scenario: 无工具链环境运行
- **WHEN** 在未安装 Swift 工具链的 Ubuntu 24.04 上解压发布 zip 并执行 `ak list`
- **THEN** 命令成功输出 skill 表格（名称/作用域/agent/路径）与汇总行，无动态链接错误

#### Scenario: 用户目录解析一致
- **WHEN** Linux 用户主目录下存在 `~/.claude/skills` 等 agent skill 目录
- **THEN** 扫描与编目结果与 macOS 语义一致（作用域判定、路径展示）

### Requirement: 双平台构建与测试纪律
CI SHALL 在 macOS 与 Linux（ubuntu-24.04）两个 job 上分别完成 core 目标（DomainKit/InfraKit/AppCore）的构建与测试，两者 MUST 全绿且沿用 0-warning 纪律；macOS 专属测试 MUST NOT 在 Linux job 执行。

#### Scenario: Linux CI 全绿
- **WHEN** 推送触发 CI
- **THEN** ubuntu-24.04 job 构建 core 目标并运行其测试套件，全部通过且无 warning

#### Scenario: 平台探针不跨平台
- **WHEN** Linux job 运行测试
- **THEN** macOS 专属 UI 探针测试（AppKit 依赖）被排除，不产生编译或运行失败

### Requirement: 发布产物矩阵覆盖 Linux
版本发布 SHALL 附带 Linux CLI 产物（`agentkeeper-cli-linux-*.zip`），与既有 macOS 产物并行；macOS 产物矩阵 MUST 保持不变。

#### Scenario: tag 发布产物齐全
- **WHEN** 推送 `v*` tag 触发 release
- **THEN** Release 附件同时包含 macOS CLI zip、macOS app zip 与 Linux CLI zip

### Requirement: 实时监听跨平台语义一致
文件系统事件监听 SHALL 按平台选用原生机制（macOS 与 Linux 各自实现），并对上层暴露一致的「整批回调」语义；`skill-catalog` 的「外部变更自动感知」行为要求 MUST 在两个平台同等满足。

#### Scenario: Linux 上外部修改自动感知
- **WHEN** 用户在 Linux 上于终端修改某 skill 的 `SKILL.md`
- **THEN** 该修改在数秒内通过整批回调反映到编目（与 macOS 行为一致），无需手动刷新
