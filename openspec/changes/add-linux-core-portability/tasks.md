# Tasks

## 1. 环境与基线（Ubuntu 24.04 开发机）

- [x] 1.1 安装 Swift 6.4.3 工具链（官方 tarball，canonical usr/bin 布局；注：strip-components 破坏工具链自定位会引发 SwiftPM 清单求值异常）
- [x] 1.2 基线：修复过程中逐项消除失败面（CoreServices/CryptoKit/AppKit/SwiftUI/SQLite3/FoundationNetworking/平台测试），最终 `swift build`/`swift test` 全绿

## 2. 依赖与平台隔离（TDD）

- [x] 2.1 Package.swift 增加 swift-crypto 依赖；`SkillParsing`/`FingerprintTests` 改 `import Crypto`；指纹测试双平台通过
- [x] 2.2 `FileMonitoring` 协议已存在（DomainKit）；新增 `FileMonitorFactory` 平台工厂；消费方（AppEnvironment）只依赖工厂
- [x] 2.3 Linux inotify 实现 `InotifyMonitor`：递归 watch（含动态补 watch/队列溢出全量提示）、聚合去抖批量送达、FdBox 竞态消除；集成测试 3 例全过
- [x] 2.4 `UpdateModel`：`terminate` 默认闭包改注入式（AppCore 零 AppKit）；UI 层注入真实退出
- [x] 2.5 `AppUpdateInstaller`：macOS 专属逻辑 `#if os(macOS)` 隔离；`AppInstalling` 协议移至 UpdateService.swift + `UnsupportedAppInstaller` 占位
- [x] 2.6 `MotionAndMenu`：`MotionPolicy`（SwiftUI 依赖）移至 AgentKeeperUI/MotionPolicy.swift；`MotionCategory` 留 AppCore；测试随迁 AgentKeeperTests
- [x] 2.7 `GitService`：注入路径不可用时按 PATH 探测回退；注入点不变
- [x] 2.8 Package.swift **零 os 分支**（见 design 决策 8：清单内 `#if` 会触发 `env -i` 编译器探测，在本机受限环境静默失败→静默空构建）；macOS 专属源文件统一文件级 `#if os(macOS)` guard；`Sources/AgentKeeper/LinuxMain.swift` Linux 占位入口
- [x] 2.9 macOS 测试探针（ProbeButton/ProbeMenuBar/UISnapshotTests 等）文件级 `#if os(macOS)` 隔离

## 3. Linux 全绿验收

- [x] 3.1 `swift build --build-system native` 全平台无关目标通过、0 编译 warning（Swift 6.4 本地；CI 用 6.2 默认即 native，无该告警）
- [x] 3.2 `swift test` 357 tests / 96 suites 全绿（含 InotifyMonitor 集成 3 例）；修复 2 处平台差异：corelibs `isHidden` 不识别点文件（Fingerprint/allRegularFiles/SnapshotDiffer 补点前缀判定，Darwin 语义不变）
- [x] 3.3 `ak` 冒烟：`ak help`/`ak list`/`ak doctor` 本机实跑——正确识别本机 agent（claude-code installed）、表格与汇总行输出正常

## 4. CI 与发布

- [x] 4.1 ci.yml 增加 ubuntu-24.04 job（swift 6.2 + libsqlite3-dev + build + test + 0-warning + ak help 冒烟）；注：swiftbuild 引擎自 6.4 起默认，Linux 侧资源包查找有缺陷，6.2 默认 native 无此问题（升级前先验证）
- [x] 4.2 release job 增加 `AgentKeeper-cli-linux-ubuntu24.04.zip`（`--static-swift-stdlib`，本机实测 89MB ELF 可产出）；macOS 产物矩阵不变
- [ ] 4.3 （推送后）观察 macos job 全绿，作为 macOS 零回归验收

## 5. 文档

- [x] 5.1 INSTALL.md 增补 Linux 安装段（下载 zip、解压、PATH、系统依赖说明）
- [x] 5.2 AGENTS.md 增补双平台构建纪律段（含「清单零 os 分支」陷阱说明）
