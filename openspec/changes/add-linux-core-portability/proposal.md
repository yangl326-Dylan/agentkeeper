# Proposal: add-linux-core-portability

## Why

产品目前只能在 macOS 构建与运行（Package.swift 仅声明 macOS 15、CI 仅 macos-15、存在 FSEvents/CryptoKit/AppKit 依赖）。Linux 用户（大量 agent CLI 用户在 Ubuntu/WSL）无法使用 `ak`；同时「core 平台无关」没有 CI 强制防线，后续 Linux GUI（`add-linux-app`）无法开工。本 change 是 Linux 支持的地基（报告 P0，见 `docs/research/2026-11-21-linux-gui-port-report.md` §3），独立交付价值明确。

## What Changes

- sha256 指纹从 `CryptoKit` 切换为 **swift-crypto**（双平台统一实现，macOS 行为零变化）
- 文件监听抽 `FileSystemMonitoring` 协议：macOS=FSEvents 实现（现行为不变），Linux=inotify 实现；上层「整批回调」语义与消费方不变
- `UpdateModel` 的 `NSApplication.terminate` 默认闭包改注入式；`AppUpdateInstaller` macOS 专属逻辑（ditto/xattr/codesign/.app）整体 `#if os(macOS)` 隔离
- `MotionPolicy`（import SwiftUI）移出 AppCore 至 AgentKeeperUI（Linux GUI 阶段再入共享层），AppCore 恢复平台无关
- git 可执行查找在 `/usr/bin/git` 默认值之外增加 PATH 回退
- CI 增加 **ubuntu-24.04 job**：core 测试（DomainKit/InfraKit/AppCore）双平台全绿 + 0-warning 纪律沿用；release 增加 `agentkeeper-cli-linux-ubuntu24.04.zip`（`--static-swift-stdlib`）
- macOS 测试探针（ProbeButton/ProbeMenuBar/UISnapshotTests 等）文件级 `#if os(macOS)` 隔离
- INSTALL.md / AGENTS.md 增补 Linux 安装段
- 不改任何 macOS 产品行为（.app 构建链、UI、发布产物矩阵保持不变）

## Capabilities

### New Capabilities

- `platform-portability`: core 与 `ak` CLI 的双平台可移植行为——Ubuntu 24.04+ 上 `ak` 的可用性与命令行为一致性、双平台构建/测试纪律、发布产物矩阵（Linux CLI 下载物）

### Modified Capabilities

（无——`skill-catalog` 等既有能力的行为要求不变；「外部变更自动感知」在 Linux 上由 inotify 实现满足同一 requirement，属实现层，进 design.md）

## Impact

- **代码**：`Sources/InfraKit`（FSEventMonitor → 协议 + 双实现；SkillParsing import）、`Sources/AppCore`（UpdateModel、AppUpdateInstaller、MotionAndMenu）、`Tests/AgentKeeperTests`（探针隔离）、`Package.swift`（依赖 + 无需平台声明变更）
- **构建/CI**：`.github/workflows/ci.yml`（新增 ubuntu job 与 release 产物）、`scripts/`（新增 Linux CLI 打包步骤）
- **依赖**：新增 `swift-crypto`（Apple 官方维护，Linux 官方支持）
- **文档**：INSTALL.md、AGENTS.md
- **后续依赖**：`add-linux-app`（Linux GUI）以本 change 为前置
