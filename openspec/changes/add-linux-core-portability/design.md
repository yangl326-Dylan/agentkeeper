# Design

## Context

Swift 6 / SwiftPM 单仓库，分层 DomainKit → InfraKit → AppCore → AgentKeeperUI → AgentKeeper/ak（见 `docs/research/2026-11-21-linux-gui-port-report.md` §2）。平台依赖面已盘点：`SkillParsing` 用 CryptoKit、`FSEventMonitor` 用 CoreServices(FSEvents)、`UpdateModel` 泄漏 `NSApplication.terminate`、`MotionAndMenu` import SwiftUI、`AppUpdateInstaller` 依赖 ditto/xattr/codesign。CI 仅 macos-15。开发/验证机为 Ubuntu 24.04（Linux 侧可本地闭环，macOS 侧依赖 CI）。

## Goals / Non-Goals

**Goals:**
- core 三目标 + `ak` 在 Linux 编译、测试全绿（0-warning 纪律不变）
- macOS 产物与行为零变化（本地无法编译 macOS，靠「只移动不改行为」的机械式改动 + CI 验证）
- 文件监听抽象后「整批回调」语义双平台一致
- Linux CLI 发布产物（静态链接 stdlib）

**Non-Goals:**
- Linux GUI（`add-linux-app`）
- Linux 应用内更新通道（隔离占位即可，实现在该后续 change）
- Windows / 其他发行版
- macOS 侧行为优化或重构（只做可移植性必需的最小移动）

## Decisions

1. **CryptoKit → swift-crypto（双平台统一）**：Apple 官方维护、API 同名（`SHA256`），Linux 官方支持。备选「平台条件编译双实现」被否：两份指纹代码漂移风险高。风险：与系统 CryptoKit 共存时选择问题——SwiftPM 同名模块冲突概率低，遇到再降级为 `#if canImport(CryptoKit)`。
2. **文件监听抽 `FileSystemMonitoring` 协议**：`func watch(paths:latency:onBatch:)` + `stop()`，回调语义=「去重路径数组、批量送达」（对齐现 FSEventMonitor 消费方式）。macOS 实现=现 FSEventMonitor 薄封装；Linux 实现=inotify 递归（对每个子目录 `add_watch(IN_MODIFY|IN_CREATE|IN_DELETE|IN_MOVED_*)`，聚合去抖后批量送达）。`ScanService/AppEnvironment` 只依赖协议。备选「轮询兜底」被否：与「数秒内反映」及资源占用不符，保留为 inotify watch 失败时的兜底注释说明。
3. **macOS 专属隔离规则**：`#if os(...)` 只允许出现在「Package.swift 平台目标声明 + 平台适配器」两类文件（落地时比原设计更干净：不采用 Linux 占位 App，而是 Package.swift 在 Linux 上只声明平台无关目标 + ak——入口文件在 Linux 不参与编译，天然无 os 分支）。`UpdateModel.terminate` 改注入默认值（默认 `{}`，UI 层注入真实退出）；`AppUpdateInstaller` 整文件隔离 + `UnsupportedAppInstaller` 平台无关占位（`AppInstalling` 协议移至 UpdateService.swift 保持双平台可见）；`MotionPolicy` 移至 AgentKeeperUI（临时居所，`add-linux-app` 时入 AgentKeeperShared），`MotionCategory`/纯决策逻辑留 AppCore。
4. **git 查找**：默认 `/usr/bin/git` 不可用时按 `PATH` 逐目录探测 `git`；注入点保持现有 `gitExecutablePath` init 参数不变。
5. **Linux 产物静态链接**：`swift build -c release --product ak --static-swift-stdlib`；系统依赖仅 glibc/libsqlite3（Ubuntu 24.04 自带 sqlite3 运行库）。产物命名 `agentkeeper-cli-linux-ubuntu24.04.zip`。
6. **CI**：ubuntu-24.04 runner + `swift-actions/setup-swift`（版本与 Xcode runner 的 Swift 6.x 对齐，作为 task 落地时按 `swift --version` 校准）；`libsqlite3-dev` apt 安装；测试排除走文件级 `#if os(macOS)`（不用 --skip 参数，保持命令简单）；0-warning 纪律 grep 同步沿用。
7. **验证策略（自我验收）**：Ubuntu 24.04 开发机本地 `swift build && swift test` 双绿 + `ak list`/`ak doctor` 实机冒烟；macOS 侧以「机械式移动 + CI macos job 全绿」为验收（推送后观察）。
8. **清单零 os 分支（实施中新发现，取代决策 3 的入口分派方案）**：Package.swift 内 `#if` 会触发 SwiftPM 清单条件编译求值——该求值以 `(cd / && env -i <swiftc> --version)` 探测编译器，在受限沙箱/精简容器里 `env -i` 子进程被静默拦截（exit 0 无输出），表现为**整个包静默空构建**（exit 0、零产物、零日志）。因此所有 target 无条件声明，平台隔离下沉到**文件级 `#if os(macOS)` guard**（UI 层源文件本就平台专属；`AgentKeeper` 入口分 macOS App 与 LinuxMain 占位两个文件）。另：Swift 6.4 起默认构建系统为 SwiftBuild（swiftbuild），其 Linux 资源包查找有缺陷（`SwiftBuild_SWB*` bundle 在 `usr/share/pm/` 但查找失败即崩溃）；现阶段 Linux 统一 `--build-system native`（CI 固定 swift 6.2，默认即 native 无告警）。

## Risks / Trade-offs

- corelibs-foundation 与 Darwin Foundation 细节差异（编码/日期/路径规范化）→ 现有 core 测试套件双平台全绿即为防线；发现平台差测试时先在测试中显式固化平台语义
- inotify 递归 watch 与 FSEvents 语义差（子目录增删需动态调整 watch 集）→ 协议层聚合去抖 + 对拍测试（临时目录增删文件断言批次内容）
- swift-testing 在 Linux runner 的已知 flake → 沿用现有 retry 包装
- 无法本地编译 macOS → 所有 macOS 侧改动保持「移动文件/调整 import」级机械操作，不做顺手重构
